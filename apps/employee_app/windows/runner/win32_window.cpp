#include "win32_window.h"

#include <dwmapi.h>

#include "resource.h"

namespace {
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

class WindowClassRegistrar {
 public:
  static WindowClassRegistrar* GetInstance() {
    static WindowClassRegistrar instance;
    return &instance;
  }

  const wchar_t* GetWindowClass() {
    if (!class_registered_) {
      WNDCLASS window_class{};
      window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
      window_class.lpszClassName = kWindowClassName;
      window_class.style = CS_HREDRAW | CS_VREDRAW;
      window_class.cbClsExtra = 0;
      window_class.cbWndExtra = 0;
      window_class.hInstance = GetModuleHandle(nullptr);
      window_class.hIcon = LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
      window_class.hbrBackground = 0;
      window_class.lpszMenuName = nullptr;
      window_class.lpfnWndProc = Win32Window::WndProc;
      RegisterClass(&window_class);
      class_registered_ = true;
    }
    return kWindowClassName;
  }

  ~WindowClassRegistrar() {
    UnregisterClass(kWindowClassName, nullptr);
  }

 private:
  bool class_registered_ = false;
};
}  // namespace

Win32Window::Win32Window() = default;
Win32Window::~Win32Window() { DestroyWindow(window_handle_); }

bool Win32Window::Create(const std::wstring& title, const Point& origin,
                         const Size& size) {
  const wchar_t* window_class = WindowClassRegistrar::GetInstance()->GetWindowClass();
  window_handle_ = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW, origin.x, origin.y,
      size.width, size.height, nullptr, nullptr, GetModuleHandle(nullptr), this);
  return window_handle_ != nullptr && OnCreate();
}

bool Win32Window::Show() { return ShowWindow(window_handle_, SW_SHOWNORMAL); }

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();
  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);
  SetFocus(child_content_);
}

HWND Win32Window::GetHandle() { return window_handle_; }
void Win32Window::SetQuitOnClose(bool quit_on_close) { quit_on_close_ = quit_on_close; }
RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

bool Win32Window::OnCreate() { return true; }
void Win32Window::OnDestroy() {}

LRESULT Win32Window::MessageHandler(HWND hwnd, UINT const message,
                                    WPARAM const wparam,
                                    LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      OnDestroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;
    case WM_SIZE:
      if (child_content_ != nullptr) {
        RECT frame = GetClientArea();
        MoveWindow(child_content_, frame.left, frame.top, frame.right - frame.left,
                   frame.bottom - frame.top, true);
      }
      return 0;
  }
  return DefWindowProc(window_handle_, message, wparam, lparam);
}

LRESULT CALLBACK Win32Window::WndProc(HWND const window, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));
    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }
  return DefWindowProc(window, message, wparam, lparam);
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(GetWindowLongPtr(window, GWLP_USERDATA));
}
