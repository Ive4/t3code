#pragma once

#include <react/renderer/components/view/ConcreteViewShadowNode.h>
#include <react/renderer/core/ConcreteComponentDescriptor.h>
#include "RNOH/Package.h"
#include "RNOHCorePackage/ComponentBinders/ViewComponentJSIBinder.h"

namespace rnoh {
inline constexpr char T3WebViewName[] = "T3WebView";

class T3WebViewBinder final : public ViewComponentJSIBinder {
  facebook::jsi::Object createNativeProps(facebook::jsi::Runtime& runtime) override {
    auto props = ViewComponentJSIBinder::createNativeProps(runtime);
    props.setProperty(runtime, "options", "string");
    return props;
  }
};

class T3WebViewPackage final : public Package {
 public:
  using Package::Package;

  std::vector<facebook::react::ComponentDescriptorProvider>
  createComponentDescriptorProviders() override {
    using namespace facebook::react;
    using Descriptor = ConcreteComponentDescriptor<ConcreteViewShadowNode<T3WebViewName>>;
    return {concreteComponentDescriptorProvider<Descriptor>()};
  }

  ComponentJSIBinderByString createComponentJSIBinderByName() override {
    return {{T3WebViewName, std::make_shared<T3WebViewBinder>()}};
  }
};
}  // namespace rnoh
