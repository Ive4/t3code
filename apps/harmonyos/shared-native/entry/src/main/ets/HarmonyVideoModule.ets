import { common } from '@kit.AbilityKit';
import { ComponentContent, PromptAction, window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { UITurboModule } from '@rnoh/react-native-openharmony';

const DIALOG_CONTENT_NOT_FOUND = 103303;

class VideoDialogParams {
  readonly controller = new VideoController();
  readonly uri: string;
  readonly title: string;
  readonly closeLabel: string;
  readonly onClose: () => void;
  readonly onError: () => void;

  constructor(
    uri: string,
    title: string,
    closeLabel: string,
    onClose: () => void,
    onError: () => void,
  ) {
    this.uri = uri;
    this.title = title;
    this.closeLabel = closeLabel;
    this.onClose = onClose;
    this.onError = onError;
  }
}

@Builder
function buildVideoDialog(params: VideoDialogParams) {
  Column() {
    Row({ space: 12 }) {
      Text(params.title)
        .fontColor(Color.White)
        .fontSize(16)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Button(params.closeLabel)
        .height(44)
        .backgroundColor(Color.Transparent)
        .fontColor(Color.White)
        .onClick(params.onClose)
    }
    .width('100%')
    .padding({ left: 20, right: 12, top: 4, bottom: 4 })

    Video({ src: params.uri, controller: params.controller })
      .width('100%')
      .layoutWeight(1)
      .objectFit(ImageFit.Contain)
      .autoPlay(true)
      .controls(true)
      .onError(() => params.onError())
  }
  .width('100%')
  .height('100%')
  .backgroundColor(Color.Black)
}

class VideoDialog {
  readonly identifier: string;
  readonly completion: Promise<void>;
  resolve: () => void = () => {};
  reject: (error: Error) => void = () => {};
  prompt: PromptAction | undefined;
  content: ComponentContent<VideoDialogParams> | undefined;
  closing = false;
  error: Error | undefined;

  constructor(identifier: string) {
    this.identifier = identifier;
    this.completion = new Promise<void>((resolve, reject) => {
      this.resolve = resolve;
      this.reject = reject;
    });
  }
}

async function videoSource(uri: string, context: common.UIAbilityContext): Promise<string> {
  if (/^https?:\/\/[^/\s?#]+/i.test(uri)) return uri;

  const encodedPath = /^file:\/\/\/([^?#]+)$/.exec(uri)?.[1];
  if (!encodedPath) throw new Error('Unsupported video URL.');
  const segments = encodedPath.split('/').map((segment: string) => decodeURIComponent(segment));
  if (segments.some((segment: string) => !segment || segment === '.' || segment === '..' || /[\/\\\x00]/.test(segment))) {
    throw new Error('Invalid video file URL.');
  }
  const path = '/' + segments.join('/');
  const root = [context.cacheDir, context.filesDir].find((candidate: string) => path.startsWith(candidate + '/'));
  if (!root) throw new Error('The video file is outside app storage.');

  const relative = path.slice(root.length + 1).split('/');
  let current = root;
  for (let index = 0; index < relative.length; index++) {
    current += '/' + relative[index];
    const info = await fileIo.lstat(current);
    if (index === relative.length - 1 ? !info.isFile() : !info.isDirectory()) {
      throw new Error('The video source is not a regular file in app storage.');
    }
  }
  return fileUri.getUriFromPath(path);
}

export class HarmonyVideoModule extends UITurboModule {
  private active: VideoDialog | undefined;
  private transition: Promise<void> = Promise.resolve();

  public present(uri: string, title: string, closeLabel: string, identifier: string): Promise<void> {
    const previous = this.active;
    if (previous) previous.closing = true;
    const dialog = new VideoDialog(identifier);
    this.active = dialog;
    void this.enqueue(async () => {
      if (previous) await this.dismiss(previous);
      if (dialog.closing) {
        this.finish(dialog);
        return;
      }
      const context = this.ctx.uiAbilityContext;
      const source = await videoSource(uri, context);
      const uiContext = (await window.getLastWindow(context)).getUIContext();
      if (dialog.closing) {
        this.finish(dialog);
        return;
      }
      const params = new VideoDialogParams(source, title, closeLabel, () => {
        void this.requestClose(dialog).catch(() => {});
      }, () => {
        if (dialog.closing) return;
        dialog.error = new Error('Video could not be played.');
        void this.requestClose(dialog).catch(() => {});
      });
      const prompt = uiContext.getPromptAction();
      const content = new ComponentContent(uiContext, wrapBuilder(buildVideoDialog), params);
      dialog.prompt = prompt;
      dialog.content = content;
      await prompt.openCustomDialog(content, {
        isModal: true,
        autoCancel: false,
        maskColor: Color.Black,
        onWillDismiss: (action: DismissDialogAction) => {
          if (action.reason !== DismissReason.TOUCH_OUTSIDE) action.dismiss();
        },
        onWillDisappear: () => {
          dialog.closing = true;
          params.controller.stop();
        },
        onDidDisappear: () => this.finish(dialog),
      });
    }).catch((error: Error) => {
      if (!dialog.closing && !dialog.error) dialog.error = error;
      this.finish(dialog);
    });
    return dialog.completion;
  }

  public async close(identifier: string): Promise<void> {
    const dialog = this.active;
    if (dialog?.identifier === identifier) await this.requestClose(dialog);
  }

  public override __onDestroy__(): void {
    const dialog = this.active;
    if (dialog) void this.requestClose(dialog).catch(() => {});
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.transition.then(operation);
    this.transition = next.catch(() => {});
    return next;
  }

  private requestClose(dialog: VideoDialog): Promise<void> {
    dialog.closing = true;
    return this.enqueue(() => this.dismiss(dialog));
  }

  private async dismiss(dialog: VideoDialog): Promise<void> {
    try {
      if (dialog.prompt && dialog.content) await dialog.prompt.closeCustomDialog(dialog.content);
    } catch (cause) {
      if (dialog.content && (cause as BusinessError).code !== DIALOG_CONTENT_NOT_FOUND) {
        const error = new Error('Video preview could not be closed.');
        dialog.reject(dialog.error ?? error);
        throw error;
      }
    }
    this.finish(dialog);
  }

  private finish(dialog: VideoDialog): void {
    if (this.active === dialog) this.active = undefined;
    const content = dialog.content;
    dialog.content = undefined;
    content?.dispose();
    if (dialog.error) dialog.reject(dialog.error);
    else dialog.resolve();
  }
}
