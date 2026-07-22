export interface DashboardStats {
  repositories: number;
  containers: number;
  cpu: number;
  memory: number;
  disk: number;
  uptime: string;
  server: string;
  hostname: string;
}

export interface ServerInfo {
  id: string;
  name: string;
  host: string;
  port: number;
  username: string;
  authMethod: string;
  os: string;
  group: string;
  status: string;
  createdAt?: string;
}

export interface Deployment {
  name: string;
  platform: string;
  institution: string;
  repository: string;
  uiPort: number;
  restPort: number;
  createdAt: string | null;
  engineReady: boolean;
}

export interface Plugin {
  name: string;
  displayName: string;
  description: string;
  status: string;
  category: string;
  reference?: string;
}

export interface AuthUser {
  id: string;
  email: string;
  role: string;
}

export interface LoginResponse {
  token: string;
  user: AuthUser;
}

export interface Job {
  id: string;
  kind: string;
  meta: Record<string, unknown>;
  status: 'running' | 'success' | 'failed';
  exitCode: number | null;
  startedAt: string;
  finishedAt: string | null;
  lines: number;
  log?: string[];
  nextCursor?: number;
}

export interface User {
  id: string;
  email: string;
  role: 'viewer' | 'engineer' | 'admin';
  createdAt?: string;
}

export interface NewDeploymentRequest {
  name: string;
  platform: string;
  institution?: string;
  repository?: string;
  adminEmail?: string;
  adminFirstName?: string;
  adminLastName?: string;
  adminPassword?: string;
  uiPort?: number;
  restPort?: number;
}

// ── Fleet (managed servers) ──
export interface FleetAgent {
  id: string;
  name: string;
  hostname: string | null;
  publicIp: string | null;
  platform?: string | null;
  version: string | null;
  license: 'active' | 'revoked';
  connectivity: 'online' | 'offline';
  enrolledAt?: string;
  lastHeartbeat: string | null;
  lastStatus?: {
    health?: string | null;
    deployments?: { name: string; platform?: string; running?: boolean }[] | null;
    at?: string;
  } | null;
  revokedAt?: string | null;
}

export interface FleetCommand {
  id: string;
  command: string;
  args?: string[];
  status: 'pending' | 'sent' | 'done' | 'failed';
  createdBy?: string | null;
  createdAt?: string;
  sentAt?: string | null;
  completedAt?: string | null;
  output?: string | null;
}

export interface EnrollmentToken {
  id: string;
  label: string;
  singleUse: boolean;
  status: 'active' | 'used' | 'expired';
  createdBy?: string | null;
  createdAt: string;
  expiresAt: string;
  usedAt?: string | null;
}

export interface IssuedToken {
  token: string;
  record: EnrollmentToken;
}
