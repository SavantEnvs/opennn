// Rejects model/dataset JSON that declares a count or dimension beyond any real one. The loaders turn
// such values straight into allocations (LayersNumber -> vector::reserve, InputDimensions -> parameter
// buffers, PreviewSize -> vector<vector<string>>); a value in the terabytes only trips ASan's
// allocation-size cap (a std::bad_alloc without it), so the fuzzer would report those instead of
// parser logic.
#pragma once

#include "opennn/core/json.h"

#include <cmath>
#include <cstddef>
#include <string>

inline constexpr double kMaxDeclaredSize = 1024;

inline bool has_oversized_integer_token(const std::string& text)
{
    std::size_t i = 0;
    while (i < text.size())
    {
        while (i < text.size() && (text[i] == ' ' || text[i] == ';' || text[i] == '\t' || text[i] == '\n')) ++i;
        const std::size_t begin = i;
        while (i < text.size() && text[i] != ' ' && text[i] != ';' && text[i] != '\t' && text[i] != '\n') ++i;
        std::size_t digits = begin;
        if (digits < i && (text[digits] == '-' || text[digits] == '+')) ++digits;
        if (digits == i) continue;
        double value = 0;
        bool integer = true;
        for (std::size_t k = digits; k < i; ++k)
        {
            if (text[k] < '0' || text[k] > '9') { integer = false; break; }
            value = value * 10 + (text[k] - '0');
        }
        if (integer && value > kMaxDeclaredSize) return true;
    }
    return false;
}

inline bool has_oversized_size(const opennn::Json& node)
{
    if (node.is_number())
    {
        const double value = node.as_double();
        return std::isfinite(value) && value == std::floor(value) && std::fabs(value) > kMaxDeclaredSize;
    }
    if (node.is_string()) return has_oversized_integer_token(node.as_string());
    if (node.is_array())
        for (const opennn::Json& item : node.as_array())
            if (has_oversized_size(item)) return true;
    if (node.is_object())
        for (const auto& member : node.as_object())
            if (has_oversized_size(member.second)) return true;
    return false;
}
