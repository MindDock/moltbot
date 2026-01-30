import type {
    ChannelAccountSnapshot,
    ChannelsStatusSnapshot,
    ConfigUiHints,
    FeishuStatus,
    WecomStatus,
} from "../types";

export type ChannelKey = string;

export type ChannelsProps = {
  connected: boolean;
  loading: boolean;
  snapshot: ChannelsStatusSnapshot | null;
  lastError: string | null;
  lastSuccessAt: number | null;
  configSchema: unknown | null;
  configSchemaLoading: boolean;
  configForm: Record<string, unknown> | null;
  configUiHints: ConfigUiHints;
  configSaving: boolean;
  configFormDirty: boolean;
  onRefresh: (probe: boolean) => void;
  onConfigPatch: (path: Array<string | number>, value: unknown) => void;
  onConfigSave: () => void;
  onConfigReload: () => void;
};

export type ChannelsChannelData = {
  feishu?: FeishuStatus | null;
  wecom?: WecomStatus | null;
  channelAccounts?: Record<string, ChannelAccountSnapshot[]> | null;
};
