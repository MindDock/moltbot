import type {
  ChannelOnboardingAdapter,
  ChannelOnboardingDmPolicy,
  MoltbotConfig,
  WizardPrompter,
} from "clawdbot/plugin-sdk";
import {
  addWildcardAllowFrom,
  DEFAULT_ACCOUNT_ID,
  normalizeAccountId,
  promptAccountId,
} from "clawdbot/plugin-sdk";

import {
  listFeishuAccountIds,
  resolveDefaultFeishuAccountId,
  resolveFeishuAccount,
} from "./accounts.js";

const channel = "feishu" as const;

function setFeishuDmPolicy(
  cfg: MoltbotConfig,
  dmPolicy: "pairing" | "allowlist" | "open" | "disabled",
) {
  const allowFrom = dmPolicy === "open" ? addWildcardAllowFrom(cfg.channels?.feishu?.allowFrom) : undefined;
  return {
    ...cfg,
    channels: {
      ...cfg.channels,
      feishu: {
        ...cfg.channels?.feishu,
        dmPolicy,
        ...(allowFrom ? { allowFrom } : {}),
      },
    },
  } as MoltbotConfig;
}

async function noteFeishuSetupHelp(prompter: WizardPrompter): Promise<void> {
  await prompter.note(
    [
      "1) Log in to Feishu Open Platform: https://open.feishu.cn/",
      "2) Create an application and get App ID and App Secret",
      "3) Enable 'Bot' capability in the app",
      "4) Configure Event Subscription with Verification Token",
      "5) (Optional) Set Encrypt Key for message encryption",
      "Docs: https://docs.molt.bot/channels/feishu",
    ].join("\n"),
    "Feishu setup",
  );
}

async function promptFeishuAllowFrom(params: {
  cfg: MoltbotConfig;
  prompter: WizardPrompter;
  accountId: string;
}): Promise<MoltbotConfig> {
  const { cfg, prompter, accountId } = params;
  const resolved = resolveFeishuAccount({ cfg, accountId });
  const existingAllowFrom = resolved.config.allowFrom ?? [];
  const entry = await prompter.text({
    message: "Feishu allowFrom (open_id or user_id)",
    placeholder: "ou_xxxxxxxx",
    initialValue: existingAllowFrom[0] ?? undefined,
    validate: (value) => {
      const raw = String(value ?? "").trim();
      if (!raw) return "Required";
      return undefined;
    },
  });
  const normalized = String(entry).trim();
  const merged = [
    ...existingAllowFrom.map((item) => String(item).trim()).filter(Boolean),
    normalized,
  ];
  const unique = [...new Set(merged)];

  if (accountId === DEFAULT_ACCOUNT_ID) {
    return {
      ...cfg,
      channels: {
        ...cfg.channels,
        feishu: {
          ...cfg.channels?.feishu,
          enabled: true,
          dmPolicy: "allowlist",
          allowFrom: unique,
        },
      },
    } as MoltbotConfig;
  }

  return {
    ...cfg,
    channels: {
      ...cfg.channels,
      feishu: {
        ...cfg.channels?.feishu,
        enabled: true,
        accounts: {
          ...(cfg.channels?.feishu?.accounts ?? {}),
          [accountId]: {
            ...(cfg.channels?.feishu?.accounts?.[accountId] ?? {}),
            enabled: cfg.channels?.feishu?.accounts?.[accountId]?.enabled ?? true,
            dmPolicy: "allowlist",
            allowFrom: unique,
          },
        },
      },
    },
  } as MoltbotConfig;
}

const dmPolicy: ChannelOnboardingDmPolicy = {
  label: "Feishu",
  channel,
  policyKey: "channels.feishu.dmPolicy",
  allowFromKey: "channels.feishu.allowFrom",
  getCurrent: (cfg) => (cfg.channels?.feishu?.dmPolicy ?? "pairing") as "pairing",
  setPolicy: (cfg, policy) => setFeishuDmPolicy(cfg as MoltbotConfig, policy),
  promptAllowFrom: async ({ cfg, prompter, accountId }) => {
    const id =
      accountId && normalizeAccountId(accountId)
        ? normalizeAccountId(accountId) ?? DEFAULT_ACCOUNT_ID
        : resolveDefaultFeishuAccountId(cfg as MoltbotConfig);
    return promptFeishuAllowFrom({
      cfg: cfg as MoltbotConfig,
      prompter,
      accountId: id,
    });
  },
};

export const feishuOnboardingAdapter: ChannelOnboardingAdapter = {
  channel,
  dmPolicy,
  getStatus: async ({ cfg }) => {
    const configured = listFeishuAccountIds(cfg as MoltbotConfig).some((accountId) => {
      const account = resolveFeishuAccount({ cfg: cfg as MoltbotConfig, accountId });
      return Boolean(account.appId && account.appSecret);
    });
    return {
      channel,
      configured,
      statusLines: [`Feishu: ${configured ? "configured" : "needs setup"}`],
      selectionHint: configured ? "recommended · configured" : "China market · enterprise",
      quickstartScore: configured ? 1 : 8,
    };
  },
  configure: async ({ cfg, prompter, accountOverrides, shouldPromptAccountIds, forceAllowFrom }) => {
    const feishuOverride = accountOverrides.feishu?.trim();
    const defaultFeishuAccountId = resolveDefaultFeishuAccountId(cfg as MoltbotConfig);
    let feishuAccountId = feishuOverride
      ? normalizeAccountId(feishuOverride)
      : defaultFeishuAccountId;
    if (shouldPromptAccountIds && !feishuOverride) {
      feishuAccountId = await promptAccountId({
        cfg: cfg as MoltbotConfig,
        prompter,
        label: "Feishu",
        currentId: feishuAccountId,
        listAccountIds: listFeishuAccountIds,
        defaultAccountId: defaultFeishuAccountId,
      });
    }

    let next = cfg as MoltbotConfig;
    const resolvedAccount = resolveFeishuAccount({ cfg: next, accountId: feishuAccountId });
    const accountConfigured = Boolean(resolvedAccount.appId && resolvedAccount.appSecret);

    if (!accountConfigured) {
      await noteFeishuSetupHelp(prompter);
    }

    // Prompt for credentials if not configured
    let appId = resolvedAccount.appId;
    let appSecret = resolvedAccount.appSecret;
    let verificationToken = resolvedAccount.config.verificationToken;
    let encryptKey = resolvedAccount.config.encryptKey;
    let webhookUrl = resolvedAccount.config.webhookUrl;

    if (!appId) {
      appId = String(
        await prompter.text({
          message: "App ID (应用ID)",
          validate: (value) => (value?.trim() ? undefined : "Required"),
        }),
      ).trim();
    }

    if (!appSecret) {
      appSecret = String(
        await prompter.text({
          message: "App Secret (应用密钥)",
          validate: (value) => (value?.trim() ? undefined : "Required"),
        }),
      ).trim();
    }

    const wantsWebhook = await prompter.confirm({
      message: "Configure event subscription for receiving messages?",
      initialValue: !verificationToken,
    });

    if (wantsWebhook) {
      if (!webhookUrl) {
        webhookUrl = String(
          await prompter.text({
            message: "Request URL (请求地址, https://...)",
            validate: (value) => (value?.trim()?.startsWith("https://") ? undefined : "HTTPS URL required"),
          }),
        ).trim();
      }

      if (!verificationToken) {
        verificationToken = String(
          await prompter.text({
            message: "Verification Token (验证令牌)",
            validate: (value) => (value?.trim() ? undefined : "Required"),
          }),
        ).trim();
      }

      const wantsEncrypt = await prompter.confirm({
        message: "Enable message encryption?",
        initialValue: Boolean(encryptKey),
      });

      if (wantsEncrypt && !encryptKey) {
        encryptKey = String(
          await prompter.text({
            message: "Encrypt Key (加密密钥)",
            validate: (value) => (value?.trim() ? undefined : "Required"),
          }),
        ).trim();
      }
    }

    // Apply configuration
    if (feishuAccountId === DEFAULT_ACCOUNT_ID) {
      next = {
        ...next,
        channels: {
          ...next.channels,
          feishu: {
            ...next.channels?.feishu,
            enabled: true,
            appId,
            appSecret,
            ...(verificationToken ? { verificationToken } : {}),
            ...(encryptKey ? { encryptKey } : {}),
            ...(webhookUrl ? { webhookUrl } : {}),
          },
        },
      } as MoltbotConfig;
    } else {
      next = {
        ...next,
        channels: {
          ...next.channels,
          feishu: {
            ...next.channels?.feishu,
            enabled: true,
            accounts: {
              ...(next.channels?.feishu?.accounts ?? {}),
              [feishuAccountId]: {
                ...(next.channels?.feishu?.accounts?.[feishuAccountId] ?? {}),
                enabled: true,
                appId,
                appSecret,
                ...(verificationToken ? { verificationToken } : {}),
                ...(encryptKey ? { encryptKey } : {}),
                ...(webhookUrl ? { webhookUrl } : {}),
              },
            },
          },
        },
      } as MoltbotConfig;
    }

    if (forceAllowFrom) {
      next = await promptFeishuAllowFrom({
        cfg: next,
        prompter,
        accountId: feishuAccountId,
      });
    }

    return { cfg: next, accountId: feishuAccountId };
  },
};
