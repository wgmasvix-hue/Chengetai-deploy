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
