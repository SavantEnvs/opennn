// Mayhem harness for opennn::TabularDataset, the public CSV loader (as used by every OpenNN example).
// The input is the CSV text. TabularDataset only reads from a path, so it is staged in $TMPDIR.
// Text the loader rejects is rejected (-1); text it accepts goes through preprocessing and statistics.
#include "opennn/dataset/tabular_dataset.h"
#include "opennn/core/log.h"

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <string>

#include <omp.h>
#include <unistd.h>

namespace
{

std::string stage_input(const std::uint8_t* data, std::size_t size)
{
    const char* tmpdir = std::getenv("TMPDIR");
    std::string path = std::string(tmpdir && *tmpdir ? tmpdir : "/tmp") + "/opennn_csv_XXXXXX";

    const int fd = mkstemp(path.data());
    if (fd < 0)
        return {};

    std::size_t written = 0;
    while (written < size)
    {
        const ssize_t n = write(fd, data + written, size - written);
        if (n <= 0)
            break;
        written += std::size_t(n);
    }
    close(fd);

    if (written != size)
    {
        unlink(path.c_str());
        return {};
    }
    return path;
}

std::string guess_separator(const std::uint8_t* data, std::size_t size)
{
    std::size_t counts[3] = {0, 0, 0};
    for (std::size_t i = 0; i < size && data[i] != '\n'; ++i)
    {
        if (data[i] == ';') ++counts[0];
        else if (data[i] == ',') ++counts[1];
        else if (data[i] == '\t') ++counts[2];
    }
    if (counts[0] >= counts[1] && counts[0] >= counts[2]) return ";";
    return counts[1] >= counts[2] ? "," : "\t";
}

}

extern "C" int LLVMFuzzerInitialize(int*, char***)
{
    opennn::logging::set_level(opennn::logging::Level::Silent);
    // One OpenMP thread: parallel loops all hit the same coverage counters, which slows every exec down.
    omp_set_num_threads(1);
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t* data, std::size_t size)
{
    if (size == 0)
        return -1;

    const std::string path = stage_input(data, size);
    if (path.empty())
        return -1;

    const std::string separator = guess_separator(data, size);
    bool loaded = false;

    for (const bool has_header : {true, false})
    {
        try
        {
            opennn::TabularDataset dataset(path, separator, has_header, false);
            dataset.set_display(false);
            loaded = true;

            (void)dataset.calculate_feature_descriptives();
            dataset.scrub_missing_values();
            (void)dataset.calculate_variable_distributions(5);
            (void)dataset.calculate_variables_box_plots();
            (void)dataset.scale_data();
        }
        catch (const std::exception&)
        {
        }
    }

    unlink(path.c_str());
    return loaded ? 0 : -1;
}
