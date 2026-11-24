#include "Parser.h"

#include <iostream>

int main(int argc, char** argv)
{
    if (argc != 2) {
        std::cerr << "usage: parser_tree <source.rs>\n";
        return 2;
    }
    syntax::ParseResult result = syntax::parseFile(argv[1]);
    if (!result) {
        std::cerr << argv[1] << ": " << result.error << '\n';
        return 1;
    }
    ast::writeDot(std::cout, *result.tree);
    std::cout.flush();
    return std::cout ? 0 : 1;
}