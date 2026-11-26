#pragma once

#include <react/renderer/components/view/ConcreteViewShadowNode.h>
#include <react/renderer/core/ConcreteComponentDescriptor.h>
#include "RNOH/Package.h"
#include "RNOHCorePackage/ComponentBinders/ViewComponentJSIBinder.h"

namespace rnoh {
inline constexpr char T3ComposerPasteName[] = "T3ComposerPaste";

class T3ComposerPasteBinder final : public ViewComponentJSIBinder {
  facebook::jsi::Object createNativeProps(facebook::jsi::Runtime& runtime) override {
    auto props = ViewComponentJSIBinder::createNativeProps(runtime);
    props.setProperty(runtime, "textOnly", "boolean");
    return props;
  }
};

class T3ComposerPastePackage final : public Package {
 public:
  using Package::Package;

  std::vector<facebook::react::ComponentDescriptorProvider>
  createComponentDescriptorProviders() override {
    using namespace facebook::react;
    using Descriptor = ConcreteComponentDescriptor<ConcreteViewShadowNode<T3ComposerPasteName>>;
    return {concreteComponentDescriptorProvider<Descriptor>()};
  }

  ComponentJSIBinderByString createComponentJSIBinderByName() override {
    return {{T3ComposerPasteName, std::make_shared<T3ComposerPasteBinder>()}};
  }
};
}  // namespace rnoh
