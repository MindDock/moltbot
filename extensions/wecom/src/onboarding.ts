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
  listWecomAccountIds,
  resolveDefaultWecomAccountId,
  resolveWecomAccount,
} from "./accounts.js";

const channel = "wecom" as const;

function setWecomDmPolicy(
  cfg: MoltbotConfig,
  dmPolicy: "pairing" | "allowlist" | "open" | "disabled",
) {
  const allowFrom = dmPolicy === "open" ? addWildcardAllowFrom(cfg.channels?.wecom?.allowFrom) : undefined;
  return {
    ...cfg,
    channels: {
      ...cfg.channels,
      wecom: {
        ...cfg.channels?.wecom,
        dmPolicy,
        ...(allowFrom ? { allowFrom } : {}),
      },
    },
  } as MoltbotConfig;
}

async function noteWecomSetupHelp(prompter: WizardPrompter): Promise<void> {
  await prompter.note(
    [
      "1) Log in to WeCom Admin: https://work.weixin.qq.com/wework_admin/frame",
      "2) Go to App Management > Create Application",
      "3) Note down: Corp ID, Agent ID, and Secret",
      "4) Set up callback (webhook) URL with Token and EncodingAESKey",
      "Docs: https://docs.molt.bot/channels/wecom",
    ].join("\n"),
    "WeCom setup",
  );
}

async function promptWecomAllowFrom(params: {
  cfg: MoltbotConfig;
  prompter: WizardPrompter;
  accountId: string;
}): Promise<MoltbotConfig> {
  const { cfg, prompter, accountId } = params;
  const resolved = resolveWecomAccount({ cfg, accountId });
  const existingAllowFrom = resolved.config.allowFrom ?? [];
  const entry = await prompter.text({
    message: "WeCom allowFrom (user id)",
    placeholder: "zhangsan",
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
        wecom: {
          ...cfg.channels?.wecom,
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
      wecom: {
        ...cfg.channels?.wecom,
        enabled: true,
        accounts: {
          ...(cfg.channels?.wecom?.accounts ?? {}),
          [accountId]: {
            ...(cfg.channels?.wecom?.accounts?.[accountId] ?? {}),
            enabled: cfg.channels?.wecom?.accounts?.[accountId]?.enabled ?? true,
            dmPolicy: "allowlist",
            allowFrom: unique,
          },
        },
      },
    },
  } as MoltbotConfig;
}

const dmPolicy: ChannelOnboardingDmPolicy = {
  label: "WeCom",
  channel,
  policyKey: "channels.wecom.dmPolicy",
  allowFromKey: "channels.wecom.allowFrom",
  getCurrent: (cfg) => (cfg.channels?.wecom?.dmPolicy ?? "pairing") as "pairing",
  setPolicy: (cfg, policy) => setWecomDmPolicy(cfg as MoltbotConfig, policy),
  promptAllowFrom: async ({ cfg, prompter, accountId }) => {
    const id =
      accountId && normalizeAccountId(accountId)
        ? normalizeAccountId(accountId) ?? DEFAULT_ACCOUNT_ID
        : resolveDefaultWecomAccountId(cfg as MoltbotConfig);
    return promptWecomAllowFrom({
      cfg: cfg as MoltbotConfig,
      prompter,
      accountId: id,
    });
  },
};

export const wecomOnboardingAdapter: ChannelOnboardingAdapter = {
  channel,
  dmPolicy,
  getStatus: async ({ cfg }) => {
    const configured = listWecomAccountIds(cfg as MoltbotConfig).some((accountId) => {
      const account = resolveWecomAccount({ cfg: cfg as MoltbotConfig, accountId });
      return Boolean(account.corpId && account.agentId && account.secret);
    });
    return {
      channel,
      configured,
      statusLines: [`WeCom: ${configured ? "configured" : "needs setup"}`],
      selectionHint: configured ? "recommended · configured" : "China market · enterprise",
      quickstartScore: configured ? 1 : 8,
    };
  },
  configure: async ({ cfg, prompter, accountOverrides, shouldPromptAccountIds, forceAllowFrom }) => {
    const wecomOverride = accountOverrides.wecom?.trim();
    const defaultWecomAccountId = resolveDefaultWecomAccountId(cfg as MoltbotConfig);
    let wecomAccountId = wecomOverride
      ? normalizeAccountId(wecomOverride)
      : defaultWecomAccountId;
    if (shouldPromptAccountIds && !wecomOverride) {
      wecomAccountId = await promptAccountId({
        cfg: cfg as MoltbotConfig,
        prompter,
        label: "WeCom",
        currentId: wecomAccountId,
        listAccountIds: listWecomAccountIds,
        defaultAccountId: defaultWecomAccountId,
      });
    }

    let next = cfg as MoltbotConfig;
    const resolvedAccount = resolveWecomAccount({ cfg: next, accountId: wecomAccountId });
    const accountConfigured = Boolean(resolvedAccount.corpId && resolvedAccount.agentId && resolvedAccount.secret);

    if (!accountConfigured) {
      await noteWecomSetupHelp(prompter);
    }

    // Prompt for credentials if not configured
    let corpId = resolvedAccount.corpId;
    let agentId = resolvedAccount.agentId;
    let secret = resolvedAccount.secret;
    let token = resolvedAccount.config.token;
    let encodingAesKey = resolvedAccount.config.encodingAesKey;
    let webhookUrl = resolvedAccount.config.webhookUrl;

    if (!corpId) {
      corpId = String(
        await prompter.text({
          message: "Corp ID (企业ID)",
          validate: (value) => (value?.trim() ? undefined : "Required"),
        }),
      ).trim();
    }

    if (!agentId) {
      agentId = String(
        await prompter.text({
          message: "Agent ID (应用ID)",
          validate: (value) => (value?.trim() ? undefined : "Required"),
        }),
      ).trim();
    }

    if (!secret) {
      secret = String(
        await prompter.text({
          message: "Secret (应用Secret)",
          validate: (value) => (value?.trim() ? undefined : "Required"),
        }),
      ).trim();
    }

    const wantsWebhook = await prompter.confirm({
      message: "Configure webhook for receiving messages?",
      initialValue: !token,
    });

    if (wantsWebhook) {
      if (!webhookUrl) {
        webhookUrl = String(
          await prompter.text({
            message: "Webhook URL (https://...)",
            validate: (value) => (value?.trim()?.startsWith("https://") ? undefined : "HTTPS URL required"),
          }),
        ).trim();
      }

      if (!token) {
        token = String(
          await prompter.text({
            message: "Token (用于验证)",
            validate: (value) => (value?.trim() ? undefined : "Required"),
          }),
        ).trim();
      }

      if (!encodingAesKey) {
        encodingAesKey = String(
          await prompter.text({
            message: "EncodingAESKey (消息加密密钥, 43 chars)",
            validate: (value) => {
              const raw = String(value ?? "").trim();
              if (raw.length !== 43) return "Must be 43 characters";
              return undefined;
            },
          }),
        ).trim();
      }
    }

    // Apply configuration
    if (wecomAccountId === DEFAULT_ACCOUNT_ID) {
      next = {
        ...next,
        channels: {
          ...next.channels,
          wecom: {
            ...next.channels?.wecom,
            enabled: true,
            corpId,
            agentId,
            secret,
            ...(token ? { token } : {}),
            ...(encodingAesKey ? { encodingAesKey } : {}),
            ...(webhookUrl ? { webhookUrl } : {}),
          },
        },
      } as MoltbotConfig;
    } else {
      next = {
        ...next,
        channels: {
          ...next.channels,
          wecom: {
            ...next.channels?.wecom,
            enabled: true,
            accounts: {
              ...(next.channels?.wecom?.accounts ?? {}),
              [wecomAccountId]: {
                ...(next.channels?.wecom?.accounts?.[wecomAccountId] ?? {}),
                enabled: true,
                corpId,
                agentId,
                secret,
                ...(token ? { token } : {}),
                ...(encodingAesKey ? { encodingAesKey } : {}),
                ...(webhookUrl ? { webhookUrl } : {}),
              },
            },
          },
        },
      } as MoltbotConfig;
    }

    if (forceAllowFrom) {
      next = await promptWecomAllowFrom({
        cfg: next,
        prompter,
        accountId: wecomAccountId,
      });
    }

    return { cfg: next, accountId: wecomAccountId };
  },
};
