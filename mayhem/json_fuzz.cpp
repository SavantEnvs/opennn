// Mayhem harness for opennn::Json (derived from upstream tools/fuzz/json_fuzz.cpp).
// Invalid text is rejected (-1); anything that parses must serialize and re-parse.
#include "opennn/core/json.h"

#include <cstddef>
#include <cstdint>
#include <exception>
#include <string>
#include <string_view>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t* data, std::size_t size)
{
    opennn::Json value;

    try
    {
        value = opennn::Json::parse(
            std::string_view(reinterpret_cast<const char*>(data), size));
    }
    catch (const std::exception&)
    {
        return -1;
    }

    const std::string serialized = value.dump(0);
    (void)opennn::Json::parse(serialized);
    (void)value.dump(2);
    return 0;
}
