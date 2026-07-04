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
