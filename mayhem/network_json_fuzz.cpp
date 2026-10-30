// Mayhem harness for opennn::Network model loading (Network::from_JSON, the parser behind Network::load
// and the JSON written by Network::save). A model that loads must serialize back to JSON.
#include "opennn/network/network.h"
#include "opennn/core/log.h"
#include "size_guard.h"

#include <cstddef>
#include <cstdint>
#include <exception>
#include <string_view>
#include <utility>

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
    opennn::logging::set_level(opennn::logging::Level::Silent);
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t* data, std::size_t size)
{
    opennn::JsonDocument document;

    try
    {
        opennn::Json root = opennn::Json::parse(
            std::string_view(reinterpret_cast<const char*>(data), size));
        if (has_oversized_size(root)) return -1;
        document.set_root(std::move(root));
    }
    catch (const std::exception&)
    {
        return -1;
    }

    try
    {
        opennn::Network network;
        network.from_JSON(document);

        opennn::JsonWriter writer;
        network.to_JSON(writer);
        (void)writer.c_str(0);
    }
    catch (const std::exception&)
    {
        return -1;
    }
    return 0;
}
