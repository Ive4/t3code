import { useIsFocused } from "@react-navigation/native";
import { CameraView, useCameraPermissions } from "expo-camera";
import { useGT } from "gt-react-native";
import { Linking, StyleSheet } from "react-native";
import * as Dialog from "../../components/ui/Dialog";

export type PairingScanResult = { readonly data: string };

export interface PairingCameraOptions {
  readonly scanComplete: boolean;
  readonly onRestart: () => void;
  readonly onScan: (result: PairingScanResult) => void;
}

export function usePairingCamera({ scanComplete, onRestart, onScan }: PairingCameraOptions) {
  const gt = useGT();
  const screenFocused = useIsFocused();
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();

  async function scan() {
    const permission = await requestCameraPermission();
    if (permission.granted) {
      onRestart();
      return;
    }
    if (permission.canAskAgain) return;
    Dialog.alert(
      gt("Camera access needed"),
      gt("Camera access was denied for this app. Open Settings to enable it."),
      [
        { text: gt("Cancel"), style: "cancel" },
        { text: gt("Open Settings"), onPress: () => void Linking.openSettings() },
      ],
    );
  }

  const preview =
    cameraPermission?.granted === true && screenFocused && !scanComplete ? (
      <CameraView
        active
        barcodeScannerSettings={{ barcodeTypes: ["qr"] }}
        onBarcodeScanned={onScan}
        style={StyleSheet.absoluteFill}
      />
    ) : null;
  return { preview, scan };
}
