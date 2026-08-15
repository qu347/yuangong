#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <shellapi.h>
#include <windows.h>

#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE* unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;
  for (int i = 1; i < argc; i++) {
    int target_length = WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, nullptr, 0, nullptr, nullptr);
    std::string utf8_arg;
    if (target_length > 0) {
      utf8_arg.resize(target_length);
      WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, utf8_arg.data(), target_length, nullptr, nullptr);
      utf8_arg.resize(target_length - 1);
    }
    command_line_arguments.push_back(utf8_arg);
  }
  ::LocalFree(argv);
  return command_line_arguments;
}
