/*++

Copyright (c) Microsoft. All rights reserved.

Module Name:

    SessionModel.h

Abstract:

    This file contains the SessionModel definition

--*/
#pragma once

#include <wslc.h>

namespace wsl::windows::wslc::models {

struct Session
{
    explicit Session(wil::com_ptr<IWSLCSession> session) : m_session(std::move(session))
    {
    }
    IWSLCSession* Get() const noexcept
    {
        return m_session.get();
    }

private:
    wil::com_ptr<IWSLCSession> m_session;
};

class SessionOptions
{
public:
    SessionOptions();

    static const std::filesystem::path& GetStoragePath();

    const WSLCSessionSettings* Get() const
    {
        return &m_sessionSettings;
    }

    WSLCSessionSettings* Get()
    {
        return &m_sessionSettings;
    }

private:
    static constexpr const wchar_t s_defaultStorageSubPath[] = L"wslc\\sessions";
    static constexpr uint32_t s_defaultBootTimeoutMs = 30 * 1000;

    WSLCSessionSettings m_sessionSettings{};
};

} // namespace wsl::windows::wslc::models