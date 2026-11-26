import {
  ComponentBuilderContext,
  Descriptor,
  RNComponentContext,
  RNViewBase,
} from '@rnoh/react-native-openharmony';
import { videoSource } from './HarmonyVideoModule';

interface VideoProps {
  nativeID: string;
  uri: string;
  initialAutoPlay: boolean;
  playbackAllowed: boolean;
  appFullscreen: boolean;
  initialPosition: number;
}

interface FullscreenEvent {
  fullscreenPosition: number;
}

type VideoDescriptor = Descriptor<string, Object, Object, VideoProps>;

// Fabric delivers numeric UIManager commands as strings.
const PAUSE_COMMAND = '1';

@Builder
export function buildT3InlineVideo(ctx: ComponentBuilderContext) {
  T3InlineVideo({ ctx: ctx.rnComponentContext, tag: ctx.tag })
}

@Component
struct T3InlineVideo {
  ctx!: RNComponentContext;
  tag: number = 0;
  @State source: string = '';
  @State playbackAllowed: boolean = false;
  private controller: VideoController = new VideoController();
  private autoplay: boolean = false;
  private viewId: string = '';
  private mounted: boolean = false;
  private appFullscreen: boolean = false;
  private initialPosition: number = 0;
  private currentPlayheadSeconds: number = 0;
  private stopUpdates?: () => void;
  private stopCommands?: () => void;

  aboutToAppear(): void {
    const props = this.ctx.descriptorRegistry.getDescriptor<VideoDescriptor>(this.tag).rawProps;
    this.viewId = props.nativeID;
    this.playbackAllowed = props.playbackAllowed;
    this.autoplay = props.initialAutoPlay && props.playbackAllowed;
    this.appFullscreen = props.appFullscreen;
    this.initialPosition = props.initialPosition;
    this.mounted = true;
    this.stopUpdates = this.ctx.descriptorRegistry.subscribeToDescriptorChanges(this.tag, (descriptor: Descriptor) => {
      const next = (descriptor as VideoDescriptor).rawProps;
      this.playbackAllowed = next.playbackAllowed;
      this.appFullscreen = next.appFullscreen;
      if (!next.initialAutoPlay) this.autoplay = false;
      if (!next.playbackAllowed) this.pause();
    });
    this.stopCommands = this.ctx.componentCommandReceiver.registerCommandCallback(this.tag, (command: string) => {
      if (command === PAUSE_COMMAND) this.pause();
    });
    void videoSource(props.uri, this.ctx.uiAbilityContext).then(source => {
      if (this.mounted) this.source = source;
    }).catch(() => this.emit('error'));
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.stopUpdates?.();
    this.stopCommands?.();
    if (this.source) this.controller.stop();
  }

  private pause(): void {
    this.autoplay = false;
    if (this.source) this.controller.pause();
  }

  private emit(event: string | FullscreenEvent): void {
    if (this.mounted) this.ctx.rnInstance.emitDeviceEvent('T3InlineVideo:' + this.viewId, event);
  }

  build() {
    RNViewBase({ tag: this.tag, ctx: this.ctx }) {
      if (this.source) {
        Video({ src: this.source, controller: this.controller })
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .controls(this.playbackAllowed)
          .onPrepared(() => {
            this.emit('prepared');
            if (this.initialPosition > 0) {
              this.controller.setCurrentTime(this.initialPosition, SeekMode.Accurate);
              this.initialPosition = 0;
            }
            if (this.autoplay && this.playbackAllowed) this.controller.start();
            this.autoplay = false;
          })
          .onUpdate((info: PlaybackInfo) => {
            this.currentPlayheadSeconds = info.time;
          })
          .onSeeked((info: PlaybackInfo) => {
            this.currentPlayheadSeconds = info.time;
          })
          .onFullscreenChange((info: FullscreenInfo) => {
            if (!info.fullscreen || !this.appFullscreen) return;
            this.controller.exitFullscreen();
            this.emit({ fullscreenPosition: this.currentPlayheadSeconds });
          })
          .onStart(() => {
            if (this.playbackAllowed) this.emit('start');
            else this.pause();
          })
          .onPause(() => this.emit('pause'))
          .onStop(() => this.emit('pause'))
          .onFinish(() => this.emit('pause'))
          .onError(() => this.emit('error'))
      }
    }
  }
}
