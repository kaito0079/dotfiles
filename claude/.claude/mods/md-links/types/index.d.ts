export type Recent = string[]

declare module 'claude-code' {
  interface PluginState {
    'md-links': { recent: Recent }
  }
}
