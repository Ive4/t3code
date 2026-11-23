#include "RNOH/ArkTSTurboModule.h"
#include "RNOH/PackageProvider.h"

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

class T3TurboModules final : public rnoh::TurboModuleFactoryDelegate {
 public:
  SharedTurboModule createTurboModule(Context context, const std::string& name)
      const override {
    if (name == "T3ConnectionStore") {
      return std::make_shared<ConnectionStore>(context, name);
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
  return {std::make_shared<T3Package>(context)};
}
