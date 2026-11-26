#include "RNKeyboardControllerPackage.h"
#include "ScreensPackage.h"
#include "SVGPackage.h"
#include "SafeAreaViewPackage.h"
#include "RNOH/ArkTSTurboModule.h"
#include "RNOH/PackageProvider.h"
#include "ReanimatedPackage.h"
#include "ReanimatedWorkletPackage.h"
#include "RnohReactNativeHarmonyGestureHandlerPackage.h"
#include "T3WebViewPackage.h"
#include "T3ComposerPastePackage.h"
#include "T3InlineVideoPackage.h"
#include "T3PdfPreviewPackage.h"

namespace {
class ConnectionStore final : public rnoh::ArkTSTurboModule {
 public:
  ConnectionStore(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(readCatalog, 0),
        ARK_ASYNC_METHOD_METADATA(writeCatalog, 1),
    };
  }
};

class PairingScanner final : public rnoh::ArkTSTurboModule {
 public:
  PairingScanner(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {ARK_ASYNC_METHOD_METADATA(scan, 0)};
  }
};

class T3AttachmentPicker final : public rnoh::ArkTSTurboModule {
 public:
  T3AttachmentPicker(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(pickDocuments, 1),
        ARK_ASYNC_METHOD_METADATA(pickMedia, 2),
    };
  }
};

class T3ImageManipulator final : public rnoh::ArkTSTurboModule {
 public:
  T3ImageManipulator(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(getSize, 1),
        ARK_ASYNC_METHOD_METADATA(render, 5),
    };
  }
};

class T3DateTimePicker final : public rnoh::ArkTSTurboModule {
 public:
  T3DateTimePicker(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {ARK_ASYNC_METHOD_METADATA(pick, 2)};
  }
};

class T3FileActions final : public rnoh::ArkTSTurboModule {
 public:
  T3FileActions(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_METHOD_METADATA(isInlinePdfAvailable, 0),
        ARK_ASYNC_METHOD_METADATA(openFile, 2),
        ARK_ASYNC_METHOD_METADATA(saveImageToLibrary, 3),
    };
  }
};

class T3AgentNotifications final : public rnoh::ArkTSTurboModule {
 public:
  T3AgentNotifications(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(isEnabled, 0),
        ARK_ASYNC_METHOD_METADATA(openSettings, 0),
        ARK_ASYNC_METHOD_METADATA(publish, 4),
        ARK_ASYNC_METHOD_METADATA(takePendingLink, 0),
        ARK_ASYNC_METHOD_METADATA(getPushToken, 0),
        ARK_ASYNC_METHOD_METADATA(isHuaweiAccountAvailable, 0),
        ARK_ASYNC_METHOD_METADATA(signInHuaweiAccount, 0),
        ARK_ASYNC_METHOD_METADATA(observePushToken, 0),
        ARK_ASYNC_METHOD_METADATA(deletePushToken, 0),
    };
  }
};

class T3FoldPosture final : public rnoh::ArkTSTurboModule {
 public:
  T3FoldPosture(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {ARK_ASYNC_METHOD_METADATA(readVerticalHinge, 0)};
  }
};

class T3UsageWidget final : public rnoh::ArkTSTurboModule {
 public:
  T3UsageWidget(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {ARK_ASYNC_METHOD_METADATA(publish, 1)};
  }
};

class T3AppGalleryUpdates final : public rnoh::ArkTSTurboModule {
 public:
  T3AppGalleryUpdates(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(isAvailable, 0),
        ARK_ASYNC_METHOD_METADATA(checkForUpdate, 0),
    };
  }
};

class T3Audio final : public rnoh::ArkTSTurboModule {
 public:
  T3Audio(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(preparePlayer, 3),
        ARK_ASYNC_METHOD_METADATA(playPlayer, 1),
        ARK_ASYNC_METHOD_METADATA(pausePlayer, 1),
        ARK_ASYNC_METHOD_METADATA(seekPlayer, 2),
        ARK_ASYNC_METHOD_METADATA(releasePlayer, 1),
        ARK_ASYNC_METHOD_METADATA(getRecordingPermission, 0),
        ARK_ASYNC_METHOD_METADATA(requestRecordingPermission, 0),
        ARK_ASYNC_METHOD_METADATA(prepareRecorder, 1),
        ARK_ASYNC_METHOD_METADATA(startRecorder, 2),
        ARK_ASYNC_METHOD_METADATA(stopRecorder, 1),
        ARK_ASYNC_METHOD_METADATA(releaseRecorder, 1),
        ARK_ASYNC_METHOD_METADATA(requestSpeech, 5),
        ARK_ASYNC_METHOD_METADATA(cancelSpeech, 1),
        ARK_ASYNC_METHOD_METADATA(checkLocalSpeechAvailability, 0),
        ARK_ASYNC_METHOD_METADATA(transcribeLocalSpeech, 2),
        ARK_ASYNC_METHOD_METADATA(cancelLocalSpeech, 1),
    };
  }
};

class T3Crypto final : public rnoh::ArkTSTurboModule {
 public:
  T3Crypto(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_METHOD_METADATA(randomUUID, 0),
        ARK_METHOD_METADATA(randomBytes, 1),
        ARK_ASYNC_METHOD_METADATA(digestBytes, 2),
        ARK_ASYNC_METHOD_METADATA(digestText, 2),
        ARK_ASYNC_METHOD_METADATA(generateDpopKey, 0),
        ARK_ASYNC_METHOD_METADATA(dpopKeyMatches, 2),
        ARK_ASYNC_METHOD_METADATA(signDpop, 2),
    };
  }
};

class T3SecureStorage final : public rnoh::ArkTSTurboModule {
 public:
  T3SecureStorage(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(getItem, 1),
        ARK_ASYNC_METHOD_METADATA(setItem, 2),
        ARK_ASYNC_METHOD_METADATA(deleteItem, 1),
        ARK_METHOD_METADATA(setDeviceOnlyItem, 2),
        ARK_ASYNC_METHOD_METADATA(getDeviceOnlyItem, 1),
        ARK_ASYNC_METHOD_METADATA(deleteDeviceOnlyItem, 1),
    };
  }
};

class T3Network final : public rnoh::ArkTSTurboModule {
 public:
  T3Network(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(getNetworkState, 0),
        ARK_METHOD_METADATA(startWatching, 0),
    };
  }
};

class T3Metadata final : public rnoh::ArkTSTurboModule {
 public:
  T3Metadata(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_METHOD_METADATA(application, 0),
        ARK_METHOD_METADATA(device, 0),
        ARK_METHOD_METADATA(is24HourFormat, 0),
    };
  }
};

class T3Interaction final : public rnoh::ArkTSTurboModule {
 public:
  T3Interaction(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(getClipboardText, 0),
        ARK_ASYNC_METHOD_METADATA(setClipboardText, 1),
        ARK_ASYNC_METHOD_METADATA(writeComposerClipboard, 2),
        ARK_ASYNC_METHOD_METADATA(takeComposerPasteImages, 2),
        ARK_ASYNC_METHOD_METADATA(setKeyboardCommands, 1),
        ARK_ASYNC_METHOD_METADATA(setComposerKeyboard, 2),
        ARK_ASYNC_METHOD_METADATA(vibrate, 1),
    };
  }
};

class T3SQLite final : public rnoh::ArkTSTurboModule {
 public:
  T3SQLite(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(open, 1),
        ARK_ASYNC_METHOD_METADATA(close, 0),
        ARK_ASYNC_METHOD_METADATA(execute, 3),
        ARK_ASYNC_METHOD_METADATA(query, 4),
        ARK_ASYNC_METHOD_METADATA(begin, 0),
        ARK_ASYNC_METHOD_METADATA(commit, 0),
        ARK_ASYNC_METHOD_METADATA(rollback, 0),
    };
  }
};

class T3Video final : public rnoh::ArkTSTurboModule {
 public:
  T3Video(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_ASYNC_METHOD_METADATA(present, 4),
        ARK_ASYNC_METHOD_METADATA(close, 1),
        ARK_ASYNC_METHOD_METADATA(thumbnail, 1),
    };
  }
};

class T3Sharing final : public rnoh::ArkTSTurboModule {
 public:
  T3Sharing(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_METHOD_METADATA(isIncomingSharingAvailable, 0),
        ARK_METHOD_METADATA(getSharedPayloads, 0),
        ARK_METHOD_METADATA(clearSharedPayloads, 0),
        ARK_METHOD_METADATA(startWatching, 0),
        ARK_METHOD_METADATA(stopWatching, 0),
        ARK_ASYNC_METHOD_METADATA(isAvailableAsync, 0),
        ARK_ASYNC_METHOD_METADATA(shareAsync, 2),
        ARK_ASYNC_METHOD_METADATA(getResolvedSharedPayloadsAsync, 0),
    };
  }
};

class T3FileSystem final : public rnoh::ArkTSTurboModule {
 public:
  T3FileSystem(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_METHOD_METADATA(getRoots, 0),
        ARK_METHOD_METADATA(stat, 1),
        ARK_METHOD_METADATA(list, 1),
        ARK_METHOD_METADATA(create, 4),
        ARK_METHOD_METADATA(remove, 2),
        ARK_METHOD_METADATA(move, 3),
        ARK_METHOD_METADATA(copySync, 3),
        ARK_METHOD_METADATA(readSync, 2),
        ARK_METHOD_METADATA(writeSync, 3),
        ARK_METHOD_METADATA(open, 2),
        ARK_METHOD_METADATA(close, 1),
        ARK_METHOD_METADATA(handleSize, 1),
        ARK_METHOD_METADATA(readChunkSync, 3),
        ARK_METHOD_METADATA(writeChunkSync, 3),
        ARK_METHOD_METADATA(cancelTransfer, 1),
        ARK_ASYNC_METHOD_METADATA(copy, 3),
        ARK_ASYNC_METHOD_METADATA(read, 2),
        ARK_ASYNC_METHOD_METADATA(write, 3),
        ARK_ASYNC_METHOD_METADATA(readChunk, 3),
        ARK_ASYNC_METHOD_METADATA(writeChunk, 3),
        ARK_ASYNC_METHOD_METADATA(upload, 5),
        ARK_ASYNC_METHOD_METADATA(download, 5),
    };
  }
};

class GtReactNative final : public rnoh::ArkTSTurboModule {
 public:
  GtReactNative(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_METHOD_METADATA(getNativeLocales, 0),
        ARK_METHOD_METADATA(nativeStoreGet, 1),
        ARK_METHOD_METADATA(nativeStoreSet, 2),
        ARK_METHOD_METADATA(multiply, 2),
    };
  }
};

class T3TurboModules final : public rnoh::TurboModuleFactoryDelegate {
 public:
  SharedTurboModule createTurboModule(Context context, const std::string& name)
      const override {
    if (name == "T3AttachmentPicker") {
      return std::make_shared<T3AttachmentPicker>(context, name);
    }
    if (name == "T3ConnectionStore") {
      return std::make_shared<ConnectionStore>(context, name);
    }
    if (name == "T3SQLite") {
      return std::make_shared<T3SQLite>(context, name);
    }
    if (name == "T3Video") {
      return std::make_shared<T3Video>(context, name);
    }
    if (name == "T3Sharing") {
      return std::make_shared<T3Sharing>(context, name);
    }
    if (name == "T3FileSystem") {
      return std::make_shared<T3FileSystem>(context, name);
    }
    if (name == "GtReactNative") {
      return std::make_shared<GtReactNative>(context, name);
    }
    if (name == "T3Interaction") {
      return std::make_shared<T3Interaction>(context, name);
    }
    if (name == "T3Metadata") {
      return std::make_shared<T3Metadata>(context, name);
    }
    if (name == "T3Network") {
      return std::make_shared<T3Network>(context, name);
    }
    if (name == "T3SecureStorage") {
      return std::make_shared<T3SecureStorage>(context, name);
    }
    if (name == "T3ImageManipulator") {
      return std::make_shared<T3ImageManipulator>(context, name);
    }
    if (name == "T3DateTimePicker") {
      return std::make_shared<T3DateTimePicker>(context, name);
    }
    if (name == "T3FileActions") {
      return std::make_shared<T3FileActions>(context, name);
    }
    if (name == "T3AgentNotifications") {
      return std::make_shared<T3AgentNotifications>(context, name);
    }
    if (name == "T3FoldPosture") {
      return std::make_shared<T3FoldPosture>(context, name);
    }
    if (name == "T3UsageWidget") {
      return std::make_shared<T3UsageWidget>(context, name);
    }
    if (name == "T3AppGalleryUpdates") {
      return std::make_shared<T3AppGalleryUpdates>(context, name);
    }
    if (name == "T3Audio") {
      return std::make_shared<T3Audio>(context, name);
    }
    if (name == "T3Crypto") {
      return std::make_shared<T3Crypto>(context, name);
    }
    if (name == "T3PairingScanner") {
      return std::make_shared<PairingScanner>(context, name);
    }
    return nullptr;
  }
};

class T3Package final : public rnoh::Package {
 public:
  using Package::Package;

  std::unique_ptr<rnoh::TurboModuleFactoryDelegate>
  createTurboModuleFactoryDelegate() override {
    return std::make_unique<T3TurboModules>();
  }
};
}  // namespace

std::vector<std::shared_ptr<rnoh::Package>> rnoh::PackageProvider::getPackages(
    rnoh::Package::Context context) {
  return {
      std::make_shared<T3Package>(context),
      std::make_shared<RnohReactNativeHarmonyGestureHandlerPackage>(context),
      std::make_shared<ReanimatedWorkletPackage>(context),
      std::make_shared<ReanimatedPackage>(context),
      std::make_shared<RNKeyboardControllerPackage>(context),
      std::make_shared<ScreensPackage>(context),
      std::make_shared<SVGPackage>(context),
      std::make_shared<SafeAreaViewPackage>(context),
      std::make_shared<rnoh::T3WebViewPackage>(context),
      std::make_shared<rnoh::T3ComposerPastePackage>(context),
      std::make_shared<rnoh::T3InlineVideoPackage>(context),
      std::make_shared<rnoh::T3PdfPreviewPackage>(context),
  };
}
