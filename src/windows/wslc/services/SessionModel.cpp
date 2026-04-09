/*++

Copyright (c) Microsoft. All rights reserved.

Module Name:

    SessionModel.cpp

Abstract:

    This file contains the SessionModel implementation.

--*/

#include <precomp.h>
#include "SessionModel.h"
#include "UserSettings.h"
#include "WSLCSessionDefaults.h"

namespace wsl::windows::wslc::models {

SessionOptions::SessionOptions()
{
    m_sessionSettings.DisplayName = wsl::windows::common::WSLCSessionDefaults::GetDefaultSessionName();
    m_sessionSettings.StoragePath = GetStoragePath().c_str();
    m_sessionSettings.CpuCount = settings::User().Get<settings::Setting::SessionCpuCount>();
    m_sessionSettings.MemoryMb = settings::User().Get<settings::Setting::SessionMemoryMb>();
    m_sessionSettings.BootTimeoutMs = s_defaultBootTimeoutMs;
    m_sessionSettings.MaximumStorageSizeMb = settings::User().Get<settings::Setting::SessionStorageSizeMb>();
    m_sessionSettings.NetworkingMode = settings::User().Get<settings::Setting::SessionNetworkingMode>();
    if (settings::User().Get<settings::Setting::SessionHostFileShareMode>() == settings::HostFileShareMode::VirtioFs)
    {
        WI_SetFlag(m_sessionSettings.FeatureFlags, WslcFeatureFlagsVirtioFs);
    }

    if (settings::User().Get<settings::Setting::SessionDnsTunneling>())
    {
        WI_SetFlag(m_sessionSettings.FeatureFlags, WslcFeatureFlagsDnsTunneling);
    }
}

const std::filesystem::path& SessionOptions::GetStoragePath()
{
    static const std::filesystem::path basePath = []() {
        return settings::User().Get<settings::Setting::SessionStoragePath>().empty()
                   ? std::filesystem::path{wsl::windows::common::filesystem::GetLocalAppDataPath(nullptr) / SessionOptions::s_defaultStorageSubPath}
                   : settings::User().Get<settings::Setting::SessionStoragePath>().c_str();
    }();

    static const std::filesystem::path storagePathNonAdmin =
        basePath / std::wstring{wsl::windows::common::WSLCSessionDefaults::defaultSessionName};
    static const std::filesystem::path storagePathAdmin =
        basePath / std::wstring{wsl::windows::common::WSLCSessionDefaults::defaultAdminSessionName};

    return wsl::windows::common::security::IsElevated() ? storagePathAdmin : storagePathNonAdmin;
}

} // namespace wsl::windows::wslc::models
