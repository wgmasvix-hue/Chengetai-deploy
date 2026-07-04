
echo ""
echo "============================================================"
echo "Deployment Complete"
echo "============================================================"

echo ""
echo "DSpace has been deployed successfully."

echo ""
echo "Frontend:"
echo "http://$SERVER_IP:4000"

echo ""
echo "Backend:"
echo "http://$SERVER_IP:8080/server/api"

echo ""
echo "============================================================"
echo "Create Administrator"
echo "============================================================"

echo ""
echo "Run the following command:"
echo ""

echo "docker exec -it dspace /dspace/bin/dspace create-administrator"

echo ""
echo "When prompted, enter:"
echo "Email      : $ADMIN_EMAIL"
echo "First Name : $ADMIN_FIRST_NAME"
echo "Last Name  : $ADMIN_LAST_NAME"

echo ""
echo "============================================================"
echo "ChengetAi Deploy Finished Successfully"
echo "============================================================"


###############################################################################
# Deployment Complete
###############################################################################

echo ""
echo "============================================================"
echo " ChengetAi Deploy : Deployment Complete"
echo "============================================================"

echo ""
echo "✓ DSpace Backend Running"
echo "✓ DSpace Frontend Running"
echo "✓ Deployment Successful"

echo ""
echo "Frontend : http://$SERVER_IP:4000"
echo "Backend  : http://$SERVER_IP:8080/server/api"

echo ""
read -rp "Create DSpace Administrator now? (Y/N): " CREATE_ADMIN

if [[ "$CREATE_ADMIN" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Launching Administrator Setup..."
    docker exec -it dspace /dspace/bin/dspace create-administrator
else
    echo ""
    echo "You can create the administrator later using:"
    echo ""
    echo "docker exec -it dspace /dspace/bin/dspace create-administrator"
fi

echo ""
echo "============================================================"
echo " ChengetAi Deploy Finished Successfully"
echo "============================================================"

