/* Copyright (c) 2023 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/ios/browser/brave_wallet/brave_wallet_ipfs_service_factory.h"

#include "brave/components/brave_wallet/browser/brave_wallet_ipfs_service.h"
#include "brave/components/brave_wallet/browser/pref_names.h"
#include "components/keyed_service/core/keyed_service.h"
#include "ios/chrome/browser/shared/model/application_context/application_context.h"
#include "ios/chrome/browser/shared/model/profile/profile_ios.h"
#include "ios/web/public/browser_state.h"

namespace brave_wallet {

// static
mojo::PendingRemote<mojom::IpfsService>
BraveWalletIpfsServiceFactory::GetForProfile(ProfileIOS* profile) {
  return GetInstance()
      ->GetServiceForProfileAs<BraveWalletIpfsService>(profile, true)
      ->MakeRemote();
}

// static
BraveWalletIpfsService* BraveWalletIpfsServiceFactory::GetServiceForState(
    ProfileIOS* profile) {
  return GetInstance()->GetServiceForProfileAs<BraveWalletIpfsService>(profile,
                                                                       true);
}

// static
BraveWalletIpfsServiceFactory* BraveWalletIpfsServiceFactory::GetInstance() {
  static base::NoDestructor<BraveWalletIpfsServiceFactory> instance;
  return instance.get();
}

BraveWalletIpfsServiceFactory::BraveWalletIpfsServiceFactory()
    : ProfileKeyedServiceFactoryIOS("BraveWalletIpfsService",
                                    ProfileSelection::kRedirectedInIncognito,
                                    ServiceCreation::kCreateLazily,
                                    TestingCreation::kNoServiceForTests) {}

BraveWalletIpfsServiceFactory::~BraveWalletIpfsServiceFactory() = default;

std::unique_ptr<KeyedService>
BraveWalletIpfsServiceFactory::BuildServiceInstanceFor(
    web::BrowserState* context) const {
  auto* profile = ProfileIOS::FromBrowserState(context);
  std::unique_ptr<BraveWalletIpfsService> ipfs_service(
      new BraveWalletIpfsService(profile->GetPrefs()));
  return ipfs_service;
}

}  // namespace brave_wallet
