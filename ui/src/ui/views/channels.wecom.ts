import { html, nothing } from "lit";

import { formatAgo } from "../format";
import type { ChannelAccountSnapshot, WecomStatus } from "../types";
import type { ChannelsProps } from "./channels.types";
import { renderChannelConfigSection } from "./channels.config";

export function renderWecomCard(params: {
  props: ChannelsProps;
  wecom?: WecomStatus;
  wecomAccounts: ChannelAccountSnapshot[];
  accountCountLabel: unknown;
}) {
  const { props, wecom, wecomAccounts, accountCountLabel } = params;
  const hasMultipleAccounts = wecomAccounts.length > 1;

  const renderAccountCard = (account: ChannelAccountSnapshot) => {
    const probe = account.probe as { bot?: { corpId?: string; agentId?: string; name?: string } } | undefined;
    const corpId = probe?.bot?.corpId;
    const agentId = probe?.bot?.agentId;
    const appName = probe?.bot?.name;
    const label = account.name || account.accountId;
    return html`
      <div class="account-card">
        <div class="account-card-header">
          <div class="account-card-title">
            ${appName || label}
          </div>
          <div class="account-card-id">
            ${corpId ? `企业ID: ${corpId}` : ""}
            ${agentId ? `应用ID: ${agentId}` : account.accountId}
          </div>
        </div>
        <div class="status-list account-card-status">
          <div>
            <span class="label">运行中</span>
            <span>${account.running ? "是" : "否"}</span>
          </div>
          <div>
            <span class="label">已配置</span>
            <span>${account.configured ? "是" : "否"}</span>
          </div>
          <div>
            <span class="label">最后接收消息</span>
            <span>${account.lastInboundAt ? formatAgo(account.lastInboundAt) : "无"}</span>
          </div>
          ${account.lastError
            ? html`
                <div class="account-card-error">
                  ${account.lastError}
                </div>
              `
            : nothing}
        </div>
      </div>
    `;
  };

  return html`
    <div class="card">
      <div class="card-title">企业微信</div>
      <div class="card-sub">企业微信应用状态和渠道配置</div>
      ${accountCountLabel}

      ${hasMultipleAccounts
        ? html`
            <div class="account-card-list">
              ${wecomAccounts.map((account) => renderAccountCard(account))}
            </div>
          `
        : html`
            <div class="status-list" style="margin-top: 16px;">
              <div>
                <span class="label">已配置</span>
                <span>${wecom?.configured ? "是" : "否"}</span>
              </div>
              <div>
                <span class="label">运行中</span>
                <span>${wecom?.running ? "是" : "否"}</span>
              </div>
              <div>
                <span class="label">最后启动</span>
                <span>${wecom?.lastStartAt ? formatAgo(wecom.lastStartAt) : "无"}</span>
              </div>
              <div>
                <span class="label">最后探测</span>
                <span>${wecom?.lastProbeAt ? formatAgo(wecom.lastProbeAt) : "无"}</span>
              </div>
              ${wecom?.webhookUrl
                ? html`
                    <div>
                      <span class="label">Webhook URL</span>
                      <span class="code-inline">${wecom.webhookUrl}</span>
                    </div>
                  `
                : nothing}
            </div>
          `}

      ${wecom?.lastError
        ? html`<div class="callout danger" style="margin-top: 12px;">
            ${wecom.lastError}
          </div>`
        : nothing}

      ${wecom?.probe
        ? html`<div class="callout" style="margin-top: 12px;">
            探测 ${wecom.probe.ok ? "成功" : "失败"} ·
            ${wecom.probe.status ?? ""} ${wecom.probe.error ?? ""}
          </div>`
        : nothing}

      ${renderChannelConfigSection({ channelId: "wecom", props })}

      <div class="row" style="margin-top: 12px;">
        <button class="btn" @click=${() => props.onRefresh(true)}>
          探测
        </button>
      </div>
    </div>
  `;
}
