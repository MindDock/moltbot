import { html, nothing } from "lit";

import { formatAgo } from "../format";
import type { ChannelAccountSnapshot, FeishuStatus } from "../types";
import type { ChannelsProps } from "./channels.types";
import { renderChannelConfigSection } from "./channels.config";

export function renderFeishuCard(params: {
  props: ChannelsProps;
  feishu?: FeishuStatus;
  feishuAccounts: ChannelAccountSnapshot[];
  accountCountLabel: unknown;
}) {
  const { props, feishu, feishuAccounts, accountCountLabel } = params;
  const hasMultipleAccounts = feishuAccounts.length > 1;

  const renderAccountCard = (account: ChannelAccountSnapshot) => {
    const probe = account.probe as { bot?: { appId?: string; name?: string } } | undefined;
    const appId = probe?.bot?.appId;
    const appName = probe?.bot?.name;
    const label = account.name || account.accountId;
    return html`
      <div class="account-card">
        <div class="account-card-header">
          <div class="account-card-title">
            ${appName || label}
          </div>
          <div class="account-card-id">${appId || account.accountId}</div>
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
      <div class="card-title">飞书</div>
      <div class="card-sub">飞书机器人状态和渠道配置</div>
      ${accountCountLabel}

      ${hasMultipleAccounts
        ? html`
            <div class="account-card-list">
              ${feishuAccounts.map((account) => renderAccountCard(account))}
            </div>
          `
        : html`
            <div class="status-list" style="margin-top: 16px;">
              <div>
                <span class="label">已配置</span>
                <span>${feishu?.configured ? "是" : "否"}</span>
              </div>
              <div>
                <span class="label">运行中</span>
                <span>${feishu?.running ? "是" : "否"}</span>
              </div>
              <div>
                <span class="label">模式</span>
                <span>${feishu?.mode ?? "无"}</span>
              </div>
              <div>
                <span class="label">最后启动</span>
                <span>${feishu?.lastStartAt ? formatAgo(feishu.lastStartAt) : "无"}</span>
              </div>
              <div>
                <span class="label">最后探测</span>
                <span>${feishu?.lastProbeAt ? formatAgo(feishu.lastProbeAt) : "无"}</span>
              </div>
              ${feishu?.webhookUrl
                ? html`
                    <div>
                      <span class="label">Webhook URL</span>
                      <span class="code-inline">${feishu.webhookUrl}</span>
                    </div>
                  `
                : nothing}
            </div>
          `}

      ${feishu?.lastError
        ? html`<div class="callout danger" style="margin-top: 12px;">
            ${feishu.lastError}
          </div>`
        : nothing}

      ${feishu?.probe
        ? html`<div class="callout" style="margin-top: 12px;">
            探测 ${feishu.probe.ok ? "成功" : "失败"} ·
            ${feishu.probe.status ?? ""} ${feishu.probe.error ?? ""}
          </div>`
        : nothing}

      ${renderChannelConfigSection({ channelId: "feishu", props })}

      <div class="row" style="margin-top: 12px;">
        <button class="btn" @click=${() => props.onRefresh(true)}>
          探测
        </button>
      </div>
    </div>
  `;
}
