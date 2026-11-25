import type { NativeThreadFile, NativeThreadFileDirectory, NativeThreadFileEntry } from '../client/ThreadFilesProtocol';

const SEARCH_FIELD_ID = 'thread-files-search-query';

class FileListData implements IDataSource {
  private entries: NativeThreadFileEntry[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.entries.length;
  }

  getData(index: number): NativeThreadFileEntry {
    return this.entries[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) this.listeners.splice(index, 1);
  }

  replace(entries: NativeThreadFileEntry[]): void {
    this.entries = entries;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}

@Component
export struct ThreadDetailFiles {
  @Prop projectTitle: string = '';
  @Prop @Watch('scrollToDirectoryStart') directory: string = '';
  @Prop @Watch('updateEntries') entries: NativeThreadFileEntry[] = [];
  @Prop fileTarget: string = '';
  @Prop preview: NativeThreadFile | undefined = undefined;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop truncated: boolean = false;
  @Prop @Watch('clearSearch') searchOpen: boolean = false;
  @Prop @Watch('clearSearch') searchContext: string = '';
  onBack: () => void = () => {};
  onRefresh: () => void = () => {};
  onOpen: (entry: NativeThreadFileEntry) => void = () => {};
  onSearch?: (query: string) => Promise<NativeThreadFileDirectory>;
  onSearchOpenChange: (open: boolean) => void = () => {};
  @State private query: string = '';
  @State private searchResult: NativeThreadFileDirectory | undefined = undefined;
  @State private searchLoading: boolean = false;
  @State private searchError: string = '';
  private listData = new FileListData();
  private listScroller = new Scroller();
  private searchData = new FileListData();
  private searchScroller = new Scroller();
  private searchController = new TextInputController();
  private focusSearchOnLayout: boolean = false;
  private searchTimer: number = -1;
  private searchGeneration: number = 0;

  aboutToAppear(): void {
    this.updateEntries();
  }

  aboutToDisappear(): void {
    clearTimeout(this.searchTimer);
    this.searchGeneration++;
  }

  private updateEntries(): void {
    this.listData.replace(this.entries);
  }

  private scrollToDirectoryStart(): void {
    this.listScroller.scrollToIndex(0);
  }

  private title(): string {
    const path = this.fileTarget;
    return path ? path.slice(path.lastIndexOf('/') + 1) : '文件';
  }

  private subtitle(): string {
    if (!this.directory) return this.projectTitle;
    return this.projectTitle ? `${this.projectTitle} · ${this.directory}` : this.directory;
  }

  private searching(): boolean {
    return this.searchOpen && !this.fileTarget && this.query.trim().length > 0;
  }

  private visibleLoading(): boolean {
    return this.searching() ? this.searchLoading : this.loading;
  }

  private visibleError(): string {
    return this.searching() ? this.searchError : this.error;
  }

  private clearSearch(): void {
    clearTimeout(this.searchTimer);
    this.searchGeneration++;
    this.query = '';
    this.searchResult = undefined;
    this.searchData.replace([]);
    this.searchError = '';
    this.searchLoading = false;
  }

  private updateSearch(query: string): void {
    if (query === this.query) return;
    this.query = query;
    this.refreshSearch(true);
  }

  private refreshSearch(debounce: boolean = false): void {
    clearTimeout(this.searchTimer);
    const generation = ++this.searchGeneration;
    this.searchResult = undefined;
    this.searchData.replace([]);
    this.searchError = '';
    this.searchLoading = this.searching();
    this.searchScroller.scrollToIndex(0);
    if (!this.searchLoading) return;
    if (debounce) {
      this.searchTimer = setTimeout(() => { void this.loadSearch(generation); }, 200);
    } else {
      void this.loadSearch(generation);
    }
  }

  private async loadSearch(generation: number): Promise<void> {
    const search = this.onSearch;
    if (!search || generation !== this.searchGeneration) return;
    try {
      const result = await search(this.query);
      if (generation !== this.searchGeneration) return;
      this.searchData.replace(result.entries);
      this.searchResult = result;
    } catch (error) {
      if (generation === this.searchGeneration) {
        this.searchError = (error as Error).message || '无法搜索工作区文件。';
      }
    } finally {
      if (generation === this.searchGeneration) this.searchLoading = false;
    }
  }

  private refresh(): void {
    if (this.searching()) this.refreshSearch();
    else this.onRefresh();
  }

  private openEntry(entry: NativeThreadFileEntry, searchResult: boolean): void {
    if (searchResult) {
      this.searchController.stopEditing();
      if (entry.kind === 'directory') this.onSearchOpenChange(false);
    }
    this.onOpen(entry);
  }

  @Builder
  private Header() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_left')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-files-back')
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .accessibilityText(this.searchOpen && !this.fileTarget ? '关闭文件搜索' : '返回')
      .onClick(() => {
        if (this.searchOpen && !this.fileTarget) this.searchController.stopEditing();
        this.onBack();
      })

      if (this.searchOpen && !this.fileTarget) {
        TextInput({ text: this.query, placeholder: '搜索文件', controller: this.searchController })
          .id(SEARCH_FIELD_ID)
          .height(44)
          .layoutWeight(1)
          .fontSize(16)
          .enterKeyType(EnterKeyType.Search)
          .cancelButton({ style: CancelButtonStyle.INPUT })
          .accessibilityText('搜索文件')
          .onChange((query: string) => this.updateSearch(query))
          .onSubmit(() => this.searchController.stopEditing())
          .onAreaChange(() => {
            if (this.focusSearchOnLayout && focusControl.requestFocus(SEARCH_FIELD_ID)) {
              this.focusSearchOnLayout = false;
            }
          })
      } else {
        Column({ space: 2 }) {
          Text(this.title())
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle()) {
            Text(this.subtitle())
              .fontSize(13)
              .fontColor($r('sys.color.font_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.onSearch && !this.fileTarget) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
          }
          .id('thread-files-search')
          .width(48)
          .height(48)
          .backgroundColor(Color.Transparent)
          .accessibilityText('搜索文件')
          .onClick(() => {
            this.focusSearchOnLayout = true;
            this.onSearchOpenChange(true);
          })
        }
      }

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(22).fontColor([$r('sys.color.icon_primary')])
      }
      .id('thread-files-refresh')
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .accessibilityText('刷新文件')
      .enabled(!this.visibleLoading())
      .onClick(() => this.refresh())
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding(4)
  }

  @Builder
  private Directory(data: FileListData, scroller: Scroller, searchResult: boolean) {
    List({ scroller }) {
      LazyForEach(data, (entry: NativeThreadFileEntry) => {
        ListItem() {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              if (entry.kind === 'directory') {
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([$r('sys.color.icon_secondary')])
              } else {
                Blank().width(12)
              }
              SymbolGlyph(entry.kind === 'directory' ? $r('sys.symbol.folder') : $r('sys.symbol.doc_plaintext'))
                .fontSize(17)
                .fontColor([entry.kind === 'directory' ? $r('sys.color.icon_emphasize') : $r('sys.color.icon_secondary')])
              Column({ space: 2 }) {
                Text(entry.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('sys.color.font_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (searchResult && entry.name !== entry.path) {
                  Text(entry.path.slice(0, entry.path.lastIndexOf('/')))
                    .fontSize(12)
                    .fontColor($r('sys.color.font_secondary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
          }
          .id(`thread-file-${entry.path}`)
          .width('100%')
          .constraintSize({ minHeight: 48 })
          .backgroundColor(Color.Transparent)
          .borderRadius(12)
          .padding({ left: 8, right: 8 })
          .accessibilityText(entry.path)
          .accessibilityDescription(entry.kind === 'directory' ? '目录' : '文件')
          .onClick(() => this.openEntry(entry, searchResult))
        }
      }, (entry: NativeThreadFileEntry) => `${entry.path}:${entry.kind}`)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
  }

  @Builder
  private Preview() {
    Scroll() {
      if (!this.preview?.contents) {
        this.Notice('文件为空。')
      } else {
        Text(this.preview.contents)
          .width('100%')
          .padding(16)
          .fontFamily('monospace')
          .fontSize(13)
          .lineHeight(19)
          .fontColor($r('sys.color.font_primary'))
          .wordBreak(WordBreak.BREAK_ALL)
          .copyOption(CopyOptions.LocalDevice)
      }
    }
    .id('thread-file-preview')
    .align(Alignment.TopStart)
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Auto)
  }

  @Builder
  private Notice(message: string) {
    Text(message)
      .width('100%')
      .fontSize(13)
      .fontColor($r('sys.color.font_secondary'))
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  build() {
    Column() {
      this.Header()

      if (this.visibleLoading()) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18)
          Text(this.searching() ? '正在搜索文件…' : '正在加载文件…')
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      }
      if (this.visibleError()) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Text(this.searching() ? '文件搜索失败' : '文件不可用')
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('sys.color.font_primary'))
            Text(this.visibleError()).fontSize(13).fontColor($r('sys.color.font_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button('重试')
            .id('thread-files-retry')
            .controlSize(ControlSize.SMALL)
            .enabled(!this.visibleLoading())
            .onClick(() => this.refresh())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      }

      if (this.preview) {
        if (this.preview.truncated) this.Notice('仅显示文件的部分内容。')
        this.Preview()
      } else if (this.searching()) {
        if (this.searchResult?.truncated) this.Notice('还有更多结果，请缩小搜索范围。')
        if ((this.searchResult?.entries.length ?? 0) > 0) {
          this.Directory(this.searchData, this.searchScroller, true)
        } else if (this.searchResult) {
          this.Notice('没有匹配的文件或目录。')
        }
      } else if (!this.fileTarget) {
        if (this.truncated) this.Notice('仅显示此目录的部分条目。')
        if (this.entries.length > 0) {
          this.Directory(this.listData, this.listScroller, false)
        } else if (!this.loading && !this.error) {
          if (this.directory) this.Notice('此目录为空。')
          else this.Notice('工作区为空。')
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
