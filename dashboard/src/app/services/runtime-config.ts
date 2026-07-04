// Reads the API URL injected at runtime by public/config.js
// (window.__CHENGETAI_CONFIG__), falling back to the build-time
// environment, then to the same host on port 3000. This lets one build
// be hosted anywhere (e.g. WebZim) and repointed by editing config.js.
import { environment } from '../../environments/environment';

export function resolveApiUrl(): string {
  const runtime = (window as any).__CHENGETAI_CONFIG__?.apiUrl;
  if (runtime) return String(runtime).replace(/\/$/, '');
  if (environment.apiUrl) return environment.apiUrl.replace(/\/$/, '');
  return `${window.location.protocol}//${window.location.hostname}:3000/api`;
}
