import {
  maskedUsageAccountEmail, nativeUsageProviderName,
} from '../client/WorkspaceUsageProtocol';
import type {
  NativeUsageAccount, NativeUsageLimitWindow, NativeUsageMetric, NativeUsagePeriod,
  NativeUsageModel, NativeUsageProvider, NativeUsageSource, NativeUsageSummary, WorkspaceUsageView,
} from '../client/WorkspaceUsageProtocol';

function formatTokens(tokens: number): string {
  if (tokens >= 1_000_000_000) return `${(tokens / 1_000_000_000).toFixed(1)}B`;
  if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
  if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(1)}K`;
  return tokens.toLocaleString();
}

function formatMetric(metric: NativeUsageMetric, view: WorkspaceUsageView): string {
  if (view === 'tokens') return formatTokens(metric.totalTokens);
  if (metric.pricedRecords === 0) return '无价格数据';
  return formatUsd(metric.costUsd);
}

function formatUsd(cost: number): string {
  return cost > 0 && cost < 0.01 ? '< $0.01' : `$${cost.toFixed(2)}`;
}

function formatShare(value: number, total: number): string {
  return `${total > 0 ? Math.round(100 * value / total) : 0}%`;
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleString();
}

function emailInitials(email: string): string {
  const parts = email.split('@');
  return `${parts[0]?.slice(0, 1) ?? ''}${parts[1]?.slice(0, 1) ?? ''}`.toUpperCase();
}

function periodLabel(period: NativeUsagePeriod): string {
  if (!period.hourStart) return period.day.slice(5);
  const date = new Date(period.hourStart);
  return `${date.getMonth() + 1}/${date.getDate()} ${date.getHours()}:${String(date.getMinutes()).padStart(2, '0')}`;
}

function periodMetricLabel(period: NativeUsagePeriod, view: WorkspaceUsageView): string {
  return `${periodLabel(period)} · ${period.empty ? '无记录' : formatMetric(period, view)}`;
}

function providerColor(provider: string): ResourceColor {
  switch (provider) {
    case 'claude': return '#d97757';
    case 'grok': return '#73737f';
    case 'cursor': return '#8b8b8b';
    case 'opencode': return '#5b9bbd';
    case 'antigravity': return '#8c7bd1';
    case 'pi': return '#4d9f8a';
    case 'muse': return '#0866ff';
    case 'codex': return $r('sys.color.font_primary');
    default: return $r('sys.color.font_emphasize');
  }
}

function remainingAtEvenPace(window: NativeUsageLimitWindow): number | undefined {
  if (!window.resetsAt || !window.windowDurationMins) return undefined;
  const duration = window.windowDurationMins * 60_000;
  const untilReset = Date.parse(window.resetsAt) - Date.now();
  return Math.round(Math.max(0, Math.min(1, untilReset / duration)) * 100);
}

@Component
export struct WorkspaceUsage {
  @Prop @Watch('reload') view: WorkspaceUsageView = 'limits';
  @Prop @Watch('reload') days: number = 30;
  @Prop @Watch('reload') environmentKey: string = '';
  @Prop environmentLabel: string = '';
  onLoadSummary?: (days: number) => Promise<NativeUsageSummary>;
  onLoadLimits?: () => Promise<NativeUsageAccount[]>;
  onOpenAccount: (account: NativeUsageAccount, window: NativeUsageLimitWindow) => void = () => {};

  @State private summary: NativeUsageSummary | undefined = undefined;
  @State private accounts: NativeUsageAccount[] = [];
  @State private loading: boolean = true;
  @State private error: string = '';
  @State private selectedPeriod: string = '';
  private visible: boolean = false;
  private generation: number = 0;
  private requestedKey: string = '';

  aboutToAppear(): void {
    this.visible = true;
    this.reload();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.generation++;
    this.requestedKey = '';
  }

  private reload(): void {
    if (!this.visible) return;
    const key = `${this.environmentKey}:${this.view === 'limits' ? 'limits' : this.days}`;
    if (this.requestedKey === key) return;
    this.requestedKey = key;
    void this.load();
  }

  private async load(): Promise<void> {
    const generation = ++this.generation;
    this.summary = undefined;
    this.accounts = [];
    this.selectedPeriod = '';
    this.error = '';
    this.loading = true;
    try {
      if (this.view === 'limits') {
        const load = this.onLoadLimits;
        if (!load) throw new Error('当前连接无法读取账户限额。');
        const accounts = await load();
        if (generation === this.generation) this.accounts = accounts;
      } else {
        const load = this.onLoadSummary;
        if (!load) throw new Error('当前连接无法读取用量统计。');
        const summary = await load(this.days);
        if (generation === this.generation) this.summary = summary;
      }
    } catch (error) {
      if (generation === this.generation) {
        this.error = (error as Error).message || '读取用量失败。';
      }
    } finally {
      if (generation === this.generation) this.loading = false;
    }
  }

  private value(metric: NativeUsageMetric): number {
    return this.view === 'tokens' ? metric.totalTokens : metric.costUsd;
  }

  private maxPeriod(summary: NativeUsageSummary): number {
    return summary.periods.reduce((max, period) => Math.max(max, this.value(period)), 0);
  }

  private highlightedPeriod(): NativeUsagePeriod | undefined {
    return this.summary?.periods.find((period) => period.key === this.selectedPeriod);
  }

  private orderedProviders(summary: NativeUsageSummary): NativeUsageProvider[] {
    return [...summary.providers].sort((left, right) => this.value(right) - this.value(left));
  }

  private orderedModels(summary: NativeUsageSummary): NativeUsageModel[] {
    return [...summary.models].sort((left, right) => this.value(right) - this.value(left));
  }

  private tokensPerActivePeriod(summary: NativeUsageSummary): string {
    const active = summary.periods.filter((period) => period.totalTokens > 0).length;
    return active > 0 ? formatTokens(Math.round(summary.totalTokens / active)) : '0';
  }

  private metricHeading(): string {
    return this.view === 'cost' ? 'Token 原始费用' : '已处理 Token';
  }

  @Builder
  private Status(message: string) {
    Column({ space: 10 }) {
      Text(message).fontSize(14).fontColor($r('sys.color.font_secondary')).textAlign(TextAlign.Center)
      Button('重试', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .height(44)
        .onClick(() => { void this.load(); })
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(24)
  }

  @Builder
  private ActivityBar(period: NativeUsagePeriod, maximum: number) {
    Column() {
      ForEach(period.providers, (provider: NativeUsageProvider) => {
        if (maximum > 0 && this.value(provider) > 0) {
          Row()
            .width('100%')
            .height(104 * this.value(provider) / maximum)
            .borderRadius(2)
            .backgroundColor(providerColor(provider.provider))
        }
      }, (provider: NativeUsageProvider) => provider.provider)
    }
    .height(104)
    .layoutWeight(1)
    .justifyContent(FlexAlign.End)
    .opacity(this.selectedPeriod && this.selectedPeriod !== period.key ? 0.6 : 1)
    .accessibilityText(periodMetricLabel(period, this.view))
    .accessibilitySelected(this.selectedPeriod === period.key)
    .onClick(() => { this.selectedPeriod = period.key; })
  }

  @Builder
  private Timeline(summary: NativeUsageSummary, maximum: number) {
    Column({ space: 10 }) {
      Text(this.days === 1 ? '按小时' : '按天')
        .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
      if (this.highlightedPeriod()) {
        Text(periodMetricLabel(this.highlightedPeriod()!, this.view))
          .fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      Row({ space: summary.periods.length > 30 ? 1 : 2 }) {
        ForEach(summary.periods, (period: NativeUsagePeriod) => {
          this.ActivityBar(period, maximum)
        }, (period: NativeUsagePeriod) => period.key)
      }
      .width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(summary.providers, (provider: NativeUsageProvider) => {
          Row({ space: 4 }) {
            Circle().width(7).height(7).fill(providerColor(provider.provider))
            Text(nativeUsageProviderName(provider.provider))
              .fontSize(12).fontColor($r('sys.color.font_secondary'))
          }
          .margin({ right: 12, bottom: 4 })
        }, (provider: NativeUsageProvider) => provider.provider)
      }
      .width('100%')
      Row() {
        Text(periodLabel(summary.periods[0])).fontSize(12).fontColor($r('sys.color.font_secondary'))
          .layoutWeight(1)
        Text(periodLabel(summary.periods[summary.periods.length - 1]))
          .fontSize(12).fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private ProviderTotals(summary: NativeUsageSummary) {
    Column() {
      ForEach(this.orderedProviders(summary), (provider: NativeUsageProvider) => {
        Column({ space: 7 }) {
          Row({ space: 12 }) {
            Circle().width(8).height(8).fill(providerColor(provider.provider))
            Text(nativeUsageProviderName(provider.provider))
              .fontSize(15).fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
            Text(formatMetric(provider, this.view))
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          }
          .width('100%')
          if (this.value(summary) > 0 && this.value(provider) > 0) {
            Progress({ value: this.value(provider), total: this.value(summary), type: ProgressType.Linear })
              .width('100%').height(4)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }, (provider: NativeUsageProvider) => provider.provider)
    }
    .width('100%')
    .borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  private SectionTitle(title: string) {
    Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_secondary'))
      .padding({ left: 4 })
  }

  @Builder
  private MetricCell(label: string, value: string, detail: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(13).fontColor($r('sys.color.font_secondary'))
      Text(value).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
      Text(detail).fontSize(12).fontColor($r('sys.color.font_secondary'))
    }
    .width('50%').alignItems(HorizontalAlign.Start).padding(14)
  }

  @Builder
  private Totals(summary: NativeUsageSummary) {
    this.SectionTitle('汇总')
    Flex({ wrap: FlexWrap.Wrap }) {
      this.MetricCell('已处理 Token', formatTokens(summary.totalTokens),
        `每个活跃${this.days === 1 ? '小时' : '日'} ${this.tokensPerActivePeriod(summary)}`)
      this.MetricCell('缓存节省', summary.pricedRecords > 0 ? formatUsd(summary.cacheSavingsUsd) : '无价格数据',
        '与完整输入价格相比')
      this.MetricCell('缓存输入', formatTokens(summary.cachedInputTokens),
        `占已观测输入 ${formatShare(summary.cachedInputTokens, summary.cachedInputTokens + summary.uncachedInputTokens)}`)
      this.MetricCell('未缓存的输入', formatTokens(summary.uncachedInputTokens),
        `缓存写入 ${formatTokens(summary.cacheCreationTokens)}`)
      this.MetricCell('输出', formatTokens(summary.outputTokens), `含推理 ${formatTokens(summary.reasoningTokens)}`)
      this.MetricCell('未定价', formatShare(summary.unpricedRecords, summary.unpricedRecords + summary.pricedRecords),
        '未计入费用的记录占比')
    }
    .width('100%').borderRadius(24).backgroundColor($r('sys.color.comp_background_primary'))
  }

  @Builder
  private CostType(label: string, cost: number, total: number) {
    if (cost > 0) {
      Row({ space: 8 }) {
        Text(label).fontSize(14).fontColor($r('sys.color.font_secondary')).layoutWeight(1)
        Text(formatShare(cost, total)).fontSize(13).fontColor($r('sys.color.font_secondary'))
        Text(formatUsd(cost)).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
      }
      .width('100%')
    }
  }

  @Builder
  private CostBreakdown(summary: NativeUsageSummary) {
    if (summary.costUsd > 0) {
      this.SectionTitle('费用')
      Column({ space: 10 }) {
        Text('按类型').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        this.CostType('输入', summary.costByType.input, summary.costUsd)
        this.CostType('缓存读取', summary.costByType.cacheRead, summary.costUsd)
        this.CostType('缓存写入', summary.costByType.cacheWrite, summary.costUsd)
        this.CostType('输出', summary.costByType.output, summary.costUsd)
        this.CostType('其他', summary.costByType.other, summary.costUsd)
        if (summary.costBySpeed.fast > 0 || summary.costBySpeed.ultrafast > 0) {
          Row({ space: 12 }) {
            Text('按速度').fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary')).layoutWeight(1)
            Text(`额外费用 ${formatUsd(summary.costBySpeed.premium)}`)
              .fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
          .width('100%').margin({ top: 6 })
          this.CostType('标准', summary.costBySpeed.standard, summary.costUsd)
          this.CostType('快速', summary.costBySpeed.fast, summary.costUsd)
          this.CostType('超快速', summary.costBySpeed.ultrafast, summary.costUsd)
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(24)
      .backgroundColor($r('sys.color.comp_background_primary'))
    }
  }

  @Builder
  private Models(summary: NativeUsageSummary) {
    if (summary.models.length > 0) {
      this.SectionTitle('按模型')
      Column() {
        ForEach(this.orderedModels(summary), (model: NativeUsageModel) => {
          Row({ space: 12 }) {
            Circle().width(8).height(8).fill(providerColor(model.provider))
            Column({ space: 3 }) {
              Text(model.model).fontSize(15).fontColor($r('sys.color.font_primary')).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${nativeUsageProviderName(model.provider)} · ${formatMetric(model, this.view === 'tokens' ? 'cost' : 'tokens')}`)
                .fontSize(13).fontColor($r('sys.color.font_secondary'))
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text(formatMetric(model, this.view))
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          }
          .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }, (model: NativeUsageModel) => model.key)
      }
      .width('100%').borderRadius(24).backgroundColor($r('sys.color.comp_background_primary'))
    }
  }

  @Builder
  private Summary(summary: NativeUsageSummary) {
    if (summary.periods.length > 0) {
      Column({ space: 16 }) {
        Column({ space: 4 }) {
          Text(this.metricHeading()).fontSize(14).fontColor($r('sys.color.font_secondary'))
          Text(formatMetric(summary, this.view))
            .fontSize(32).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
          if (this.view === 'cost' && summary.pricedRecords > 0) {
            Text('按 API 公布价格估算').fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
          if (this.view === 'tokens' && summary.sources.length > 0) {
            Text(`${summary.sessions.toLocaleString()} 个会话`)
              .fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
          if (this.view === 'cost' && summary.unpricedRecords > 0) {
            Text(`${summary.unpricedRecords.toLocaleString()} 条记录缺少价格`)
              .fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        if (this.view === 'tokens' || summary.pricedRecords > 0) this.Timeline(summary, this.maxPeriod(summary))
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(24)
      .backgroundColor($r('sys.color.comp_background_primary'))
      this.SectionTitle('提供商')
      this.ProviderTotals(summary)
      this.Totals(summary)
      this.CostBreakdown(summary)
      this.Models(summary)
    } else {
      this.Status(summary.sources.some((source) => source.status === 'partial' || source.status === 'failed') ?
        '用量来源读取不完整。' : '所选时间内没有用量记录。')
    }
    ForEach(summary.sources, (source: NativeUsageSource) => {
      if (source.status === 'partial' || source.status === 'failed' || source.refreshing) {
        Text(`${nativeUsageProviderName(source.provider)} · ${source.refreshing ? '正在刷新用量' : source.message || '用量读取不完整'}`)
          .fontSize(13).fontColor($r('sys.color.font_secondary')).padding({ left: 4 })
      }
    })
  }

  @Builder
  private LimitRow(account: NativeUsageAccount, window: NativeUsageLimitWindow) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(window.label).fontSize(14).fontColor($r('sys.color.font_primary')).layoutWeight(1)
          Text(`剩余 ${window.remainingPercent}%`)
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([$r('sys.color.icon_secondary')])
        }
        .width('100%')
        Progress({ value: window.remainingPercent, total: 100, type: ProgressType.Linear })
          .width('100%').height(4)
        if (window.resetsAt) {
          Text(`重置于 ${formatTime(window.resetsAt)}`).fontSize(12).fontColor($r('sys.color.font_secondary'))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .id(`workspace-usage-account-${account.id}-${window.id}`)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .accessibilityText(`${account.name}，${window.label}，剩余 ${window.remainingPercent}%`)
    .onClick(() => this.onOpenAccount(account, window))
  }

  @Builder
  private LimitCard(account: NativeUsageAccount) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(account.name).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)
        if (account.email) {
          Text(emailInitials(account.email)).fontSize(10).fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_secondary')).backgroundColor($r('sys.color.comp_background_tertiary'))
            .width(22).height(22).borderRadius(11).textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      if (account.plan) Text(account.plan).fontSize(13).fontColor($r('sys.color.font_secondary'))
      if (account.zeroSpendCap) {
        Text('每月支出上限为 $0。').fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      if (account.unavailable) {
        Text(account.unavailable).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
      ForEach(account.windows, (window: NativeUsageLimitWindow) => {
        this.LimitRow(account, window)
      }, (window: NativeUsageLimitWindow) => window.id)
      if (account.windows.length === 0 && !account.zeroSpendCap && !account.unavailable) {
        Text('当前账户没有可显示的限额窗口。').fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }

  build() {
    Column({ space: 14 }) {
      if (this.environmentLabel) {
        Text(this.environmentLabel).fontSize(13).fontColor($r('sys.color.font_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 4 })
      }
      if (this.loading) {
        Row({ space: 8 }) {
          LoadingProgress().width(22).height(22)
          Text('正在读取用量…').fontSize(14).fontColor($r('sys.color.font_secondary'))
        }
        .width('100%').justifyContent(FlexAlign.Center).padding(20)
      } else if (this.error) {
        this.Status(this.error)
      } else if (this.view === 'limits') {
        if (this.accounts.length === 0) {
          this.Status('当前环境没有可显示的账户限额。')
        } else {
          ForEach(this.accounts, (account: NativeUsageAccount) => {
            this.LimitCard(account)
          }, (account: NativeUsageAccount) => account.id)
        }
      } else if (this.summary) {
        this.Summary(this.summary)
      }
    }
    .id('workspace-usage-content')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct WorkspaceUsageAccount {
  @Prop @Watch('hideEmail') account: NativeUsageAccount | undefined = undefined;
  @Prop window: NativeUsageLimitWindow | undefined = undefined;
  @Prop environmentLabel: string = '';
  onBack: () => void = () => {};
  @State private revealed: boolean = false;

  private hideEmail(): void {
    this.revealed = false;
  }

  @Builder
  private AccountDetails(account: NativeUsageAccount, window: NativeUsageLimitWindow, pace: number | undefined) {
    Column({ space: 8 }) {
      Text(account.name).fontSize(22).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
      if (account.email) {
        Button(this.revealed ? account.email : maskedUsageAccountEmail(account.email), {
          type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL,
        })
          .id('workspace-usage-account-email')
          .constraintSize({ minHeight: 44 })
          .padding(0)
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
          .accessibilityText(this.revealed ? `${account.email}，隐藏账户邮箱` : '显示账户邮箱')
          .onClick(() => { this.revealed = !this.revealed; })
      }
      if (account.plan) {
        Text(account.plan).fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
    Column({ space: 10 }) {
      Text(window.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
      Text(`剩余 ${window.remainingPercent}%`)
        .fontSize(30).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary'))
      if (window.resetsAt) {
        Text(`重置于 ${formatTime(window.resetsAt)}`).fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      if (pace !== undefined) {
        Text(`按均匀使用速度应剩余 ${pace}%`)
          .fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      if (window.modelIds && window.modelIds.length > 0) {
        Text(window.modelIds.join(' · ')).fontSize(13).fontColor($r('sys.color.font_secondary'))
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(24)
    .backgroundColor($r('sys.color.comp_background_primary'))
    if (this.environmentLabel) {
      Column({ space: 8 }) {
        Text('已登录的环境').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        Text(this.environmentLabel).fontSize(14).fontColor($r('sys.color.font_secondary'))
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(24)
      .backgroundColor($r('sys.color.comp_background_primary'))
    }
    if (account.resetCredits) {
      Column({ space: 8 }) {
        Text('重置额度').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
        Text(`可用 ${account.resetCredits.availableCount} 次`).fontSize(14).fontColor($r('sys.color.font_secondary'))
        if (account.resetCredits.nextExpiresAt) {
          Text(`最早到期 ${formatTime(account.resetCredits.nextExpiresAt)}`)
            .fontSize(14).fontColor($r('sys.color.font_secondary'))
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding(16).borderRadius(24)
      .backgroundColor($r('sys.color.comp_background_primary'))
    }
  }

  build() {
    Column() {
      Row({ space: 4 }) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
        }
        .id('workspace-usage-account-back')
        .width(48).height(48).padding(0).accessibilityText('返回用量').onClick(this.onBack)
        Text('账户').fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('sys.color.font_primary')).layoutWeight(1)
      }
      .width('100%').height(56).padding({ left: 12, right: 12 })
      Scroll() {
        Column({ space: 16 }) {
          if (this.account && this.window) {
            this.AccountDetails(this.account, this.window, remainingAtEvenPace(this.window))
          } else {
            Text('当前环境未报告此账户的限额。').fontSize(14).fontColor($r('sys.color.font_secondary'))
          }
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      }
      .width('100%').layoutWeight(1).align(Alignment.Top)
    }
    .id('workspace-usage-account')
    .width('100%').height('100%').backgroundColor($r('sys.color.comp_background_tertiary'))
  }
}
