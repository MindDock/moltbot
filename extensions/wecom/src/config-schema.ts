import { MarkdownConfigSchema } from "clawdbot/plugin-sdk";
import { z } from "zod";

const wecomAccountSchema = z.object({
  name: z.string().optional(),
  enabled: z.boolean().optional(),
  markdown: MarkdownConfigSchema,
  corpId: z.string().optional(),
  agentId: z.string().optional(),
  secret: z.string().optional(),
  token: z.string().optional(),
  encodingAesKey: z.string().optional(),
  webhookUrl: z.string().optional(),
  webhookPath: z.string().optional(),
  dmPolicy: z.enum(["pairing", "allowlist", "open", "disabled"]).optional(),
  allowFrom: z.array(z.string()).optional(),
  mediaMaxMb: z.number().optional(),
});

export const WecomConfigSchema = wecomAccountSchema.extend({
  accounts: z.object({}).catchall(wecomAccountSchema).optional(),
  defaultAccount: z.string().optional(),
});
