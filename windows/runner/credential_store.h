#ifndef BROOMM_CREDENTIAL_STORE_H_
#define BROOMM_CREDENTIAL_STORE_H_
#include <windows.h>
#include <wincred.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <memory>
#include <string>

// OS credential I/O only; all account/token workflows remain in Dart.
inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterCredentialStore(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "app.broomm/credentials", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const std::string* key = nullptr;
    const std::string* value = nullptr;
    if (args) {
      const auto k = args->find(flutter::EncodableValue("key"));
      if (k != args->end()) key = std::get_if<std::string>(&k->second);
      const auto v = args->find(flutter::EncodableValue("value"));
      if (v != args->end()) value = std::get_if<std::string>(&v->second);
    }
    auto fail = [&]() { result->Error("secure_store", "Secure sign-in storage is unavailable or invalid."); };
    const std::string identity = key && key->rfind("sgdb-", 0) == 0 ? key->substr(5) : (key ? *key : "");
    if (identity.size() != 32 || !std::all_of(identity.begin(), identity.end(),
        [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); })) { fail(); return; }
    std::wstring target = L"Broomm/RomM/v1/";
    target.append(key->begin(), key->end());
    if (call.method_name() == "read") {
      PCREDENTIALW item = nullptr;
      if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &item)) {
        if (GetLastError() == ERROR_NOT_FOUND) result->Success(); else fail();
        return;
      }
      if (item->CredentialBlobSize > CRED_MAX_CREDENTIAL_BLOB_SIZE) { CredFree(item); fail(); return; }
      std::string secret;
      if (item->CredentialBlobSize) secret.assign(reinterpret_cast<char*>(item->CredentialBlob), item->CredentialBlobSize);
      CredFree(item);
      result->Success(flutter::EncodableValue(secret));
    } else if (call.method_name() == "write") {
      if (!value || value->size() > CRED_MAX_CREDENTIAL_BLOB_SIZE) { fail(); return; }
      CREDENTIALW item{};
      item.Type = CRED_TYPE_GENERIC;
      item.TargetName = target.data();
      item.CredentialBlobSize = static_cast<DWORD>(value->size());
      item.CredentialBlob = reinterpret_cast<LPBYTE>(const_cast<char*>(value->data()));
      item.Persist = CRED_PERSIST_LOCAL_MACHINE;
      if (CredWriteW(&item, 0)) result->Success(); else fail();
    } else if (call.method_name() == "delete") {
      if (CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0) || GetLastError() == ERROR_NOT_FOUND) result->Success(); else fail();
    } else result->NotImplemented();
  });
  return channel;
}
#endif
