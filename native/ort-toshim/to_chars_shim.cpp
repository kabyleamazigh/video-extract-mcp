// ---------------------------------------------------------------------------
// macOS 12 (Intel) compatibility shim for prebuilt ONNX Runtime binaries.
//
// onnxruntime-node ships prebuilt darwin-x64 binaries (libonnxruntime.*.dylib)
// linked against a libc++ newer than the one in macOS 12: they need the C++17
// floating-point std::to_chars overloads (std::__1::to_chars(char*, char*,
// float|double|long double[, chars_format[, int]])) which only exist from
// macOS 13. dlopen() therefore fails with
//
//   Symbol not found: __ZNSt3__18to_charsEPcS0_d
//     Expected in: /usr/lib/libc++.1.dylib
//
// which makes the whole ONNX native backend unusable on such a machine.
//
// This shim defines exactly those 9 symbols. ort-macos12-shim.sh compiles it
// into `cxx.dylib`, drops it beside the ORT dylib and re-points that dylib's
// /usr/lib/libc++.1.dylib dependency at it with install_name_tool: only the
// missing symbols come from the shim, everything else keeps resolving against
// the real libc++, which the shim re-exports (-Wl,-reexport-lc++).
//
// DYLD_INSERT_LIBRARIES / DYLD_FORCE_FLAT_NAMESPACE are deliberately not used:
// the redirection belongs to the dylib, so it applies to every process that
// loads it -- including the short-lived worker src/vision/embed.ts spawns --
// with no environment plumbing at all, and since the ORT dylib is unsigned the
// redirection needs neither sudo nor re-signing.
//
// Notes:
//  * The return type is not part of the Itanium C++ ABI mangling for
//    non-template functions, so the local OrtShimToCharsResult only has to be
//    layout compatible with libc++'s std::to_chars_result { char* ptr; errc ec; }
//    -- which it is (pointer + int).
//  * The functions are defined inside `std::__1` purely to produce the exact
//    mangled names the ORT dylib looks for; clang does not object.
//  * Formatting uses snprintf with round-trip precisions (17 for double, 9 for
//    float, 21 for long double). Not guaranteed to be the *shortest*
//    representation libc++ would produce, but a correct and round-trippable
//    one, which is all ONNX Runtime needs.
// ---------------------------------------------------------------------------

#include <cerrno>
#include <cstddef>
#include <cstdio>

// Layout-compatible stand-in for std::to_chars_result.
struct OrtShimToCharsResult {
  char* ptr;
  int ec;
};

// std::errc::value_too_large maps to EOVERFLOW in libc++.
enum { kOrtShimOk = 0, kOrtShimValueTooLarge = EOVERFLOW };

#define ORT_SHIM_EXPORT __attribute__((visibility("default")))

// Formats `value` into [first, last).
static OrtShimToCharsResult ortShimToChars(char* first, char* last, long double value,
                                           unsigned fmtBits, int precision,
                                           bool isLongDouble) {
  if (precision < 0) precision = isLongDouble ? 21 : 17;

  const bool scientific = (fmtBits & 1u) != 0;
  const bool fixed = (fmtBits & 2u) != 0;
  const bool hex = (fmtBits & 4u) != 0;

  char conv = 'g';
  if (hex) {
    conv = 'a';
  } else if (scientific && !fixed) {
    conv = 'e';
  } else if (fixed && !scientific) {
    conv = 'f';
  }

  char spec[8];
  int i = 0;
  spec[i++] = '%';
  spec[i++] = '.';
  spec[i++] = '*';
  if (isLongDouble) spec[i++] = 'L';
  spec[i++] = conv;
  spec[i] = '\0';

  char buf[512];
  // The variadic argument must match the conversion specifier exactly: long
  // double only when the "L" length modifier is present.
  int n = isLongDouble ? std::snprintf(buf, sizeof(buf), spec, precision, value)
                       : std::snprintf(buf, sizeof(buf), spec, precision, (double)value);
  if (n < 0) return OrtShimToCharsResult{first, kOrtShimOk};
  if (static_cast<std::size_t>(n) > static_cast<std::size_t>(last - first))
    return OrtShimToCharsResult{last, kOrtShimValueTooLarge};
  for (int k = 0; k < n; ++k) first[k] = buf[k];
  return OrtShimToCharsResult{first + n, kOrtShimOk};
}

namespace std {
inline namespace __1 {

// Must be declared here so the mangled parameter type is std::__1::chars_format
// (NS_12chars_formatE), matching the ORT dylib's undefined references.
enum class chars_format : unsigned {
  scientific = 1,
  fixed = 2,
  hex = 4,
  general = fixed | scientific,
};

ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, float value) {
  return ortShimToChars(first, last, value, 3u, -1, false);
}
ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, double value) {
  return ortShimToChars(first, last, value, 3u, -1, false);
}
ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, long double value) {
  return ortShimToChars(first, last, value, 3u, -1, true);
}

ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, float value,
                                              chars_format fmt) {
  return ortShimToChars(first, last, value, static_cast<unsigned>(fmt), -1, false);
}
ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, double value,
                                              chars_format fmt) {
  return ortShimToChars(first, last, value, static_cast<unsigned>(fmt), -1, false);
}
ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, long double value,
                                              chars_format fmt) {
  return ortShimToChars(first, last, value, static_cast<unsigned>(fmt), -1, true);
}

ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, float value,
                                              chars_format fmt, int precision) {
  return ortShimToChars(first, last, value, static_cast<unsigned>(fmt), precision, false);
}
ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, double value,
                                              chars_format fmt, int precision) {
  return ortShimToChars(first, last, value, static_cast<unsigned>(fmt), precision, false);
}
ORT_SHIM_EXPORT OrtShimToCharsResult to_chars(char* first, char* last, long double value,
                                              chars_format fmt, int precision) {
  return ortShimToChars(first, last, value, static_cast<unsigned>(fmt), precision, true);
}

}  // namespace __1
}  // namespace std