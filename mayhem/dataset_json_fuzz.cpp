// Mayhem harness for opennn::TabularDataset definition loading (TabularDataset::from_JSON, the parser
// behind Dataset::load and the JSON written by Dataset::save). A definition that loads must serialize back.
#include "opennn/dataset/tabular_dataset.h"
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
        opennn::TabularDataset dataset;
        dataset.from_JSON(document);

        opennn::JsonWriter writer;
        dataset.to_JSON(writer);
        (void)writer.c_str(0);
    }
    catch (const std::exception&)
    {
        return -1;
    }
    return 0;
}
