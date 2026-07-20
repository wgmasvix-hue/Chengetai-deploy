#!/usr/bin/env bash
# chengetai backup [name] [--schedule daily|weekly|monthly] [--keep N]
#                         [--offsite 'CMD'] [--unschedule] [--run]
#
# With no flags: run a one-off backup now (plugin_backup), then apply
# retention and the off-site hook if they are configured.
#   --schedule    install a systemd timer to back this deployment up on a
#                 schedule (root). --keep and --offsite are remembered.
#   --keep N      keep only the N most recent backups (prune older).
#   --offsite CMD run CMD after each backup with $BACKUP_DIR set (e.g. an
#                 rsync or 'aws s3 sync' to push the backup off the server).
#   --unschedule  remove the schedule (root).
#   --run         internal: what the timer invokes (same as a one-off).
set -e

source "$(dirname "$0")/utils.sh"

NAME="" MODE="oneoff" SCHEDULE="" KEEP="" OFFSITE="" HAVE_KEEP=0 HAVE_OFFSITE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --schedule)   MODE="schedule"; SCHEDULE="$2"; shift 2 ;;
        --unschedule) MODE="unschedule"; shift ;;
        --run)        MODE="run"; shift ;;
        --keep)       KEEP="$2"; HAVE_KEEP=1; shift 2 ;;
        --offsite)    OFFSITE="$2"; HAVE_OFFSITE=1; shift 2 ;;
        -*)           error "Unknown option: $1" ;;
        *)            NAME="$1"; shift ;;
    esac
done

resolve_deployment "$NAME"

BKENV="$DEPLOY_DIR/backup.env"
# Load remembered schedule/keep/offsite, then let CLI flags override.
# shellcheck source=/dev/null
[ -f "$BKENV" ] && . "$BKENV"
[ "$HAVE_KEEP" = "1" ] && BK_KEEP="$KEEP"
[ "$HAVE_OFFSITE" = "1" ] && BK_OFFSITE="$OFFSITE"
[ -n "$SCHEDULE" ] && BK_SCHEDULE="$SCHEDULE"

SVC="/etc/systemd/system/chengetai-backup-$DEPLOY_NAME.service"
TMR="/etc/systemd/system/chengetai-backup-$DEPLOY_NAME.timer"

save_backup_env() {
    umask 077
    {
        printf 'BK_SCHEDULE=%q\n' "${BK_SCHEDULE:-}"
        printf 'BK_KEEP=%q\n'     "${BK_KEEP:-}"
        printf 'BK_OFFSITE=%q\n'  "${BK_OFFSITE:-}"
    } > "$BKENV"
    chmod 600 "$BKENV"
}

apply_retention() {
    local keep="${BK_KEEP:-}"
    [ -n "$keep" ] || return 0
    local dir="$DEPLOY_DIR/backups" count
    count=$(find "$dir" -maxdepth 1 -type d -name 'chengetai-backup-*' 2>/dev/null | wc -l)
    if [ "$count" -gt "$keep" ]; then
        # Oldest first; delete all but the newest $keep.
        find "$dir" -maxdepth 1 -type d -name 'chengetai-backup-*' | sort | head -n -"$keep" | while read -r old; do
            info "Pruning old backup: $(basename "$old")"
            rm -rf "$old"
        done
    fi
}

run_offsite() {
    [ -n "${BK_OFFSITE:-}" ] || return 0
    local latest
    latest=$(find "$DEPLOY_DIR/backups" -maxdepth 1 -type d -name 'chengetai-backup-*' 2>/dev/null | sort | tail -1)
    [ -n "$latest" ] || return 0
    info "Running off-site backup command..."
    if BACKUP_DIR="$latest" DEPLOY_NAME="$DEPLOY_NAME" bash -c "$BK_OFFSITE"; then
        info "Off-site backup done."
    else
        warn "Off-site backup command failed (exit $?)."
    fi
}

do_backup() {
    require_docker
    banner "Backing Up : $DEPLOY_NAME"
    plugin_backup
    apply_retention
    run_offsite
}

install_timer() {
    [ "$(id -u)" = "0" ] || error "Scheduling backups needs root: sudo chengetai backup $DEPLOY_NAME --schedule ${BK_SCHEDULE:-daily}"
    command -v systemctl >/dev/null 2>&1 || error "systemd is required to schedule backups."
    local oncal
    case "${BK_SCHEDULE:-}" in
        daily)   oncal="*-*-* 02:00:00" ;;
        weekly)  oncal="Sun *-*-* 02:00:00" ;;
        monthly) oncal="*-*-01 02:00:00" ;;
        *)       error "Unknown schedule '${BK_SCHEDULE:-}'. Use: daily | weekly | monthly." ;;
    esac
    # Default retention for scheduled backups so disks don't fill.
    [ -n "${BK_KEEP:-}" ] || BK_KEEP=7
    save_backup_env

    cat > "$SVC" <<EOF
[Unit]
Description=ChengetAi backup for $DEPLOY_NAME
After=docker.service

[Service]
Type=oneshot
Environment=CHENGETAI_HOME=$CHENGETAI_HOME
Environment=CHENGETAI_DEPLOYMENTS_DIR=$DEPLOYMENTS_DIR
ExecStart=/usr/bin/env bash $CHENGETAI_HOME/chengetai backup $DEPLOY_NAME --run
EOF
    cat > "$TMR" <<EOF
[Unit]
Description=ChengetAi backup timer for $DEPLOY_NAME ($BK_SCHEDULE)

[Timer]
OnCalendar=$oncal
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now "chengetai-backup-$DEPLOY_NAME.timer"
    banner "Scheduled backups — $DEPLOY_NAME"
    echo "  Schedule : $BK_SCHEDULE (at 02:00)"
    echo "  Keep     : $BK_KEEP most recent"
    [ -n "${BK_OFFSITE:-}" ] && echo "  Off-site : $BK_OFFSITE"
    echo "  Next run : $(systemctl list-timers "chengetai-backup-$DEPLOY_NAME.timer" --no-legend 2>/dev/null | awk '{print $1, $2}')"
    echo "  Logs     : journalctl -u chengetai-backup-$DEPLOY_NAME.service"
}

remove_timer() {
    [ "$(id -u)" = "0" ] || error "Requires root: sudo chengetai backup $DEPLOY_NAME --unschedule"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "chengetai-backup-$DEPLOY_NAME.timer" 2>/dev/null || true
        rm -f "$SVC" "$TMR"
        systemctl daemon-reload
    fi
    BK_SCHEDULE=""
    save_backup_env
    info "Scheduled backups removed for $DEPLOY_NAME (existing backups are kept)."
}

case "$MODE" in
    schedule)   install_timer ;;
    unschedule) remove_timer ;;
    run|oneoff) do_backup ;;
esac
