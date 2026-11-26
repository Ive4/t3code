import { TurboModuleRegistry, type TurboModule } from "react-native";

interface VideoThumbnail {
  readonly uri: string;
  readonly width: number;
  readonly height: number;
}

interface NativeVideo extends TurboModule {
  thumbnail(uri: string): Promise<VideoThumbnail | null>;
}

export async function extractVideoFrame(uri: string): Promise<VideoThumbnail | null> {
  return (await TurboModuleRegistry.get<NativeVideo>("T3Video")?.thumbnail(uri)) ?? null;
}
