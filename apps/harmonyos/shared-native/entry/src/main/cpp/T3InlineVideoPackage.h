#pragma once

#include <react/renderer/components/view/ConcreteViewShadowNode.h>
#include <react/renderer/core/ConcreteComponentDescriptor.h>
#include "RNOH/Package.h"
#include "RNOHCorePackage/ComponentBinders/ViewComponentJSIBinder.h"

namespace rnoh {
inline constexpr char T3InlineVideoName[] = "T3InlineVideo";

class T3InlineVideoBinder final : public ViewComponentJSIBinder {
  facebook::jsi::Object createNativeProps(facebook::jsi::Runtime& runtime) override {
    auto props = ViewComponentJSIBinder::createNativeProps(runtime);
    props.setProperty(runtime, "uri", "string");
    props.setProperty(runtime, "initialAutoPlay", "boolean");
    props.setProperty(runtime, "playbackAllowed", "boolean");
    props.setProperty(runtime, "appFullscreen", "boolean");
    props.setProperty(runtime, "initialPosition", "number");
    return props;
  }
};

class T3InlineVideoPackage final : public Package {
 public:
  using Package::Package;

  std::vector<facebook::react::ComponentDescriptorProvider>
  createComponentDescriptorProviders() override {
    using namespace facebook::react;
    using Descriptor = ConcreteComponentDescriptor<ConcreteViewShadowNode<T3InlineVideoName>>;
    return {concreteComponentDescriptorProvider<Descriptor>()};
  }

  ComponentJSIBinderByString createComponentJSIBinderByName() override {
    return {{T3InlineVideoName, std::make_shared<T3InlineVideoBinder>()}};
  }
};
}  // namespace rnoh
