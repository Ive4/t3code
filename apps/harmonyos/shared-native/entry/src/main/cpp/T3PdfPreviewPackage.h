#pragma once

#include <react/renderer/components/view/ConcreteViewShadowNode.h>
#include <react/renderer/core/ConcreteComponentDescriptor.h>
#include "RNOH/Package.h"
#include "RNOHCorePackage/ComponentBinders/ViewComponentJSIBinder.h"

namespace rnoh {
inline constexpr char T3PdfPreviewName[] = "T3PdfPreview";

class T3PdfPreviewBinder final : public ViewComponentJSIBinder {
  facebook::jsi::Object createNativeProps(facebook::jsi::Runtime& runtime) override {
    auto props = ViewComponentJSIBinder::createNativeProps(runtime);
    props.setProperty(runtime, "uri", "string");
    props.setProperty(runtime, "initialPage", "number");
    return props;
  }
};

class T3PdfPreviewPackage final : public Package {
 public:
  using Package::Package;

  std::vector<facebook::react::ComponentDescriptorProvider>
  createComponentDescriptorProviders() override {
    using namespace facebook::react;
    using Descriptor = ConcreteComponentDescriptor<ConcreteViewShadowNode<T3PdfPreviewName>>;
    return {concreteComponentDescriptorProvider<Descriptor>()};
  }

  ComponentJSIBinderByString createComponentJSIBinderByName() override {
    return {{T3PdfPreviewName, std::make_shared<T3PdfPreviewBinder>()}};
  }
};
}  // namespace rnoh
