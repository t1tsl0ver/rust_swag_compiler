#pragma once

#include "Ast.h"

#include <memory>
#include <string>

namespace syntax {

struct ParseResult {
    std::unique_ptr<ast::Program> tree;
    std::string error;
    unsigned int lexerErrors = 0;

    explicit operator bool() const { return tree != nullptr && error.empty() && lexerErrors == 0; }
};

ParseResult parseFile(const std::string& filename);

}