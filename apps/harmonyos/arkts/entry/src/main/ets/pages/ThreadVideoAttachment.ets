import { threadAttachmentCachePath } from '../client/ThreadAttachmentCachePath';
import { fileUri } from '@kit.CoreFileKit';

@Component
export struct ThreadVideoAttachment {
  @Prop @Watch('selectVideo') uri: string = '';
  @Prop @Watch('updatePaused') paused: boolean = false;
  onRetry?: () => void;
  onPlaybackSuccess?: () => void;

  @State private source: string = '';
  @State private status: 'loading' | 'ready' | 'error' = 'loading';
  private controller: VideoController = new VideoController();
  private mounted: boolean = false;
  private generation: number = 0;
  private playing: boolean = false;
  private resumePlayback: boolean = false;
  private reportedPlayback: boolean = false;

  aboutToAppear(): void {
    this.mounted = true;
    this.selectVideo();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.generation++;
    this.stopVideo();
  }

  private current(generation: number): boolean {
    return this.mounted && this.generation === generation;
  }

  private stopVideo(): void {
    if (this.source) this.controller.stop();
    this.playing = false;
    this.resumePlayback = false;
  }

  private selectVideo(): void {
    if (!this.mounted) return;
    const generation = ++this.generation;
    this.stopVideo();
    this.source = '';
    this.status = 'loading';
    this.reportedPlayback = false;
    void this.loadVideo(this.uri, generation);
  }

  private async loadVideo(uri: string, generation: number): Promise<void> {
    try {
      const cacheDir = this.getUIContext().getHostContext()?.cacheDir ?? '';
      const source = fileUri.getUriFromPath(await threadAttachmentCachePath(uri, cacheDir));
      if (this.current(generation)) this.source = source;
    } catch (_) {
      if (this.current(generation)) this.status = 'error';
    }
  }

  private updatePaused(): void {
    if (!this.mounted || !this.source) return;
    if (this.paused && this.playing) {
      this.resumePlayback = true;
      this.controller.pause();
    } else if (!this.paused && this.resumePlayback) {
      this.resumePlayback = false;
      this.controller.start();
    }
  }

  @Builder
  private Player(source: string, generation: number) {
    Video({ src: source, controller: this.controller })
      .id('thread-attachment-video')
      .width('100%').height('100%').objectFit(ImageFit.Contain)
      .autoPlay(true).controls(true)
      .onPrepared(() => {
        if (this.current(generation)) this.status = 'ready';
      })
      .onStart(() => {
        if (!this.current(generation)) return;
        this.playing = true;
        if (this.paused) this.updatePaused();
        else if (!this.reportedPlayback) {
          this.reportedPlayback = true;
          this.onPlaybackSuccess?.();
        }
      })
      .onPause(() => {
        if (this.current(generation)) this.playing = false;
      })
      .onFinish(() => {
        if (this.current(generation)) this.playing = false;
      })
      .onError(() => {
        if (!this.current(generation)) return;
        this.generation++;
        this.stopVideo();
        this.source = '';
        this.status = 'error';
      })
  }

  build() {
    Stack() {
      if (this.source) this.Player(this.source, this.generation)
      if (this.status === 'loading') {
        Column({ space: 10 }) {
          LoadingProgress().width(26).height(26).color(Color.White)
          Text('正在加载视频…').fontSize(14).fontColor('#D1D5DB')
        }.id('thread-attachment-video-loading')
      } else if (this.status === 'error') {
        Column({ space: 10 }) {
          Text('无法播放视频').fontSize(17).fontWeight(FontWeight.Medium).fontColor(Color.White)
          Text('请检查环境连接或视频格式。').fontSize(14).fontColor('#D1D5DB').textAlign(TextAlign.Center)
          if (this.onRetry) {
            Button('重试').id('thread-attachment-video-retry').height(44).onClick(() => this.onRetry?.())
          }
        }.id('thread-attachment-video-error').width('100%').padding(24)
      }
    }.width('100%').height('100%').backgroundColor(Color.Black)
  }
}
