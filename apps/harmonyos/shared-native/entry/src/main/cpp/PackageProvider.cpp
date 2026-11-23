#include "RNKeyboardControllerPackage.h"
#include "ScreensPackage.h"
#include "SVGPackage.h"
#include "SafeAreaViewPackage.h"
#include "RNOH/ArkTSTurboModule.h"
#include "RNOH/PackageProvider.h"
#include "ReanimatedPackage.h"
#include "ReanimatedWorkletPackage.h"
#include "RnohReactNativeHarmonyGestureHandlerPackage.h"

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

class T3Crypto final : public rnoh::ArkTSTurboModule {
 public:
  T3Crypto(Context context, const std::string& name)
      : ArkTSTurboModule(context, name) {
    methodMap_ = {
        ARK_METHOD_METADATA(randomUUID, 0),
        ARK_METHOD_METADATA(randomBytes, 1),
        ARK_ASYNC_METHOD_METADATA(digestBytes, 2),
        ARK_ASYNC_METHOD_METADATA(digestText, 2),
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
  };
}
