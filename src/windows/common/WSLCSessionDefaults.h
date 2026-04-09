
/*++

Copyright (c) Microsoft. All rights reserved.

Module Name:

    WSLCSessionDefaults.h

Abstract:

    This file contains default WSLC session name helpers.

--*/

#pragma once

#include <string>
#include "WslSecurity.h"
#include "stringshared.h"

namespace wsl::windows::common {

class WSLCSessionDefaults
{
public:
    // These are elevation-aware static methods that will return the correct
    // session name or validate against the correct session name based on the
    // elevation of the process.
    static const wchar_t* GetDefaultSessionName()
    {
        return wsl::windows::common::security::IsElevated() ? defaultAdminSessionName : defaultSessionName;
    }

    static bool IsDefaultSessionName(const std::wstring& sessionName)
    {
        return wsl::shared::string::IsEqual(sessionName, GetDefaultSessionName());
    }

    static constexpr const wchar_t defaultSessionName[] = L"wslc-cli";
    static constexpr const wchar_t defaultAdminSessionName[] = L"wslc-cli-admin";
};

} // namespace wsl::windows::common