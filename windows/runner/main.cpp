#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Production builds are a WINDOWS-subsystem GUI app. The stock Flutter
  // template only AllocConsole() under a debugger, so launching
  // front_porch_ai.exe from cmd/PowerShell attached the parent console but
  // never rebound stdout/stderr — the prompt looked idle and RAG/engine
  // logs never appeared. Fix:
  //   1) Attach to parent console when launched from a terminal, and rebind
  //      stdout/stderr there — but ONLY when the process arrived without a
  //      usable stdout. The flutter tool (flutter run / flutter test
  //      -d windows) launches this exe with stdout/stderr bound to pipes it
  //      reads — the Dart VM service URI travels over that pipe, so
  //      rebinding it to CONOUT$ starves the tool and it waits forever
  //      (CI's Windows E2E leg hung to its job timeout exactly this way).
  //      A direct cmd/PowerShell launch of a GUI-subsystem exe gets NULL
  //      std handles, which is the case the redirect exists for.
  //   2) --console forces a dedicated console (double-click / shortcuts).
  //   3) Debugger still gets a console (Flutter default).
  const bool force_console =
      command_line != nullptr && wcsstr(command_line, L"--console") != nullptr;
  const HANDLE inherited_stdout = ::GetStdHandle(STD_OUTPUT_HANDLE);
  const bool stdout_already_bound =
      inherited_stdout != nullptr && inherited_stdout != INVALID_HANDLE_VALUE;
  if (::AttachConsole(ATTACH_PARENT_PROCESS)) {
    if (!stdout_already_bound) {
      RedirectIoToConsole();
    }
  } else if (force_console || ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // Draw with Skia. Impeller smears and ghosts text while a local model is
  // working the GPU (seen on macOS and on Windows; flutter/flutter#193927),
  // and Skia was the renderer before Flutter 3.47. Remove this line to try
  // Impeller again once that issue is fixed. macOS has the same switch in
  // Runner/Info.plist and Linux in runner/my_application.cc.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Front Porch AI", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
