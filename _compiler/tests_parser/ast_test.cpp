#include "Parser.h"

#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>

namespace {

void check(bool condition, const char* message)
{
    if (!condition) {
        throw std::runtime_error(message);
    }
}

template <typename Kind, typename Node, typename Deleter>
const Kind& as(const std::unique_ptr<Node, Deleter>& node)
{
    check(node != nullptr, "expected an AST node");
    return std::get<Kind>(node->kind);
}

const ast::ExprPtr& statementExpression(const ast::Stmt& statement)
{
    return std::get<ast::ExprStmt>(statement.kind).expression;
}

std::string dotNodeId(const std::string& dot, const std::string& label)
{
    const auto labelPosition = dot.find(" [label=\"" + label + "\", shape=");
    check(labelPosition != std::string::npos, "DOT must display call and argument labels");
    const auto lineStart = dot.rfind("\n  n", labelPosition);
    check(lineStart != std::string::npos, "DOT node must have an ID");
    const auto idStart = lineStart + 3;
    return dot.substr(idStart, labelPosition - idStart);
}

void checkDeclarations(const ast::Module& module)
{
    const auto& pair = as<ast::Struct>(module.items.at(0));
    check(std::get<ast::TupleFields>(pair.fields).size() == 2, "tuple struct fields");
    const auto& choices = as<ast::Enum>(module.items.at(2)).variants;
    check(std::holds_alternative<ast::UnitFields>(choices.at(0).fields), "unit variant");
    const auto& discriminant = as<ast::LiteralExpr>(choices.at(1).discriminant);
    check(std::get<unsigned long long>(discriminant.token.value) == 1, "variant discriminant");
    check(std::get<ast::NamedFields>(choices.at(2).fields).size() == 1, "named variant");

    const auto& trait = as<ast::Trait>(module.items.at(3));
    const auto& signature = as<ast::Function>(trait.items.at(1));
    check(!signature.body, "trait declaration must have no body");
    check(std::get<ast::Receiver>(signature.parameters.at(0)).kind == ast::ReceiverKind::Reference,
          "method receiver");

    const auto& implementation = as<ast::Impl>(module.items.at(4));
    check(implementation.trait && implementation.trait->at(0).text == "Read", "impl trait");
    const auto& method = as<ast::Function>(implementation.items.at(1));
    check(method.body && as<ast::TupleFieldExpr>(method.body->tail).index == "0",
          "tuple field as a tail expression");
}

void checkBody(const ast::Function& function)
{
    check(function.parameters.size() == 2, "parameter count");
    check(std::get<ast::NamedParam>(function.parameters.at(0)).mutableBinding, "mutable parameter");
    const auto& obj = std::get<ast::NamedParam>(function.parameters.at(1));
    check(as<ast::ReferenceType>(obj.type).mutableReference, "mutable reference type");

    check(function.body != nullptr, "function body");
    const auto& statements = function.body->statements;
    check(statements.size() == 13, "block statement count");
    const auto& local = std::get<ast::LetStmt>(statements.at(0).kind);
    check(local.mutableBinding && local.type && !local.initializer, "mutable declaration without initializer");
    const auto& raw = std::get<ast::LetStmt>(statements.at(1).kind);
    check(raw.name.text == "type" && raw.name.raw, "raw identifier");
    as<ast::IfExpr>(as<ast::ParenthesizedExpr>(raw.initializer).inner);

    check(!std::get<ast::ExprStmt>(statements.at(2).kind).hasSemicolon, "non-final bare if");
    check(!std::get<ast::ExprStmt>(statements.at(3).kind).hasSemicolon, "if is a block expression statement");
    check(std::holds_alternative<ast::EmptyStmt>(statements.at(4).kind) &&
          std::holds_alternative<ast::EmptyStmt>(statements.at(5).kind), "semicolons after if are empty statements");

    const auto& call = as<ast::CallExpr>(statementExpression(statements.at(6)));
    const auto& callee = as<ast::PathExpr>(call.callee).path;
    check(callee.size() == 2 && callee.at(0).text == "pkg" && callee.at(1).text == "call", "callee path");
    check(call.arguments.size() == 3, "argument count with trailing comma");
    check(std::get<unsigned long long>(as<ast::LiteralExpr>(call.arguments.at(0)).token.value) == 1 &&
          std::get<unsigned long long>(as<ast::LiteralExpr>(call.arguments.at(1)).token.value) == 2,
          "argument order and literal values");
    as<ast::IfExpr>(as<ast::ParenthesizedExpr>(call.arguments.at(2)).inner);
    const auto& method = as<ast::MethodCallExpr>(statementExpression(statements.at(7)));
    check(method.method.text == "method" && method.arguments.size() == 2, "method call");
    const auto& field = as<ast::FieldExpr>(statementExpression(statements.at(8)));
    check(field.member.text == "callback", "field access");
    const auto& direct = as<ast::CallExpr>(statementExpression(statements.at(9)));
    check(as<ast::PathExpr>(direct.callee).path.at(0).text == "f", "unqualified function call");
    as<ast::IndexExpr>(statementExpression(statements.at(10)));

    const auto& value = std::get<ast::LetStmt>(statements.at(11).kind);
    const auto& sum = as<ast::BinaryExpr>(value.initializer);
    check(sum.op == ast::BinaryOp::Add && as<ast::BinaryExpr>(sum.right).op == ast::BinaryOp::Multiply,
          "operator precedence");
    const auto& structure = as<ast::StructExpr>(statementExpression(statements.at(12)));
    const auto& structField = structure.fields.at(0);
    check(structField.name.text == "value" && as<ast::PathExpr>(structField.value).path.at(0).text == "value",
          "explicit struct field value");

    const auto& tail = as<ast::IfExpr>(function.body->tail);
    check(tail.thenBlock && tail.thenBlock->tail && tail.elseBranch, "if as a block tail");
}

void checkNestedControlFlow(const ast::Program& program)
{
    const auto& search = as<ast::Function>(program.items.at(0));
    check(search.body != nullptr, "search function body");
    const auto& rows = as<ast::ForExpr>(statementExpression(search.body->statements.at(0)));
    const auto& columns = as<ast::WhileExpr>(rows.body->tail);

    const auto& gap = as<ast::IfExpr>(statementExpression(columns.body->statements.at(0)));
    as<ast::ContinueExpr>(statementExpression(gap.thenBlock->statements.at(1)));

    const auto& found = std::get<ast::LetStmt>(columns.body->statements.at(1).kind);
    const auto& scan = as<ast::LoopExpr>(as<ast::ParenthesizedExpr>(found.initializer).inner);
    const auto& endOfRun = as<ast::IfExpr>(statementExpression(scan.body->statements.at(0)));
    const auto& stop = as<ast::BreakExpr>(statementExpression(endOfRun.thenBlock->statements.at(0)));
    check(as<ast::LiteralExpr>(stop.value).token.spelling == "false", "break at end of run");

    const auto& positive = as<ast::IfExpr>(endOfRun.elseBranch);
    const auto& match = as<ast::IfExpr>(positive.thenBlock->tail);
    const auto& pair = as<ast::CallExpr>(match.condition);
    check(as<ast::PathExpr>(pair.callee).path.at(0).text == "matches_pair" && pair.arguments.size() == 3,
          "pair check with three arguments");
    as<ast::IndexExpr>(pair.arguments.at(0));
    const auto& normalize = as<ast::CallExpr>(pair.arguments.at(1));
    check(as<ast::PathExpr>(normalize.callee).path.at(0).text == "normalize",
          "nested call in second argument");
    as<ast::IndexExpr>(normalize.arguments.at(0));
    const auto& success = as<ast::BreakExpr>(statementExpression(match.thenBlock->statements.at(0)));
    check(as<ast::LiteralExpr>(success.value).token.spelling == "true", "break on matching pair");

    const auto& result = as<ast::IfExpr>(columns.body->tail);
    as<ast::ReturnExpr>(statementExpression(result.thenBlock->statements.at(0)));

    std::ostringstream output;
    ast::writeDot(output, program);
    const auto dot = output.str();
    check(dot.find("label=\"while column + 1 < 4 { ... }\"") != std::string::npos &&
          dot.find("label=\"column = column + 1;\"") != std::string::npos &&
          dot.find("label=\"if matches_pair(row[column], normalize(row[column + 1]), target) { ... }\"") !=
              std::string::npos,
          "DOT must display Rust expressions");
    const auto callId = dotNodeId(dot, "matches_pair(row[column], normalize(row[column + 1]), target)");
    const auto argumentId = dotNodeId(dot, "normalize(row[column + 1])");
    check(dot.find("  " + callId + " -> " + argumentId + " [label=\"argument 2\"];") != std::string::npos,
          "DOT must show normalize as the second argument of matches_pair");
}

} // namespace

int main(int argc, char** argv)
{
    if (argc != 2 && argc != 4) {
        return 2;
    }
    try {
        if (argc == 4) {
            const auto invalid = syntax::parseFile(argv[2]);
            check(!invalid && !invalid.tree && !invalid.error.empty() && invalid.lexerErrors == 0,
                  "syntax error must reject the AST");
            const auto lexicalError = syntax::parseFile(argv[3]);
            check(!lexicalError && !lexicalError.tree && lexicalError.lexerErrors > 0,
                  "lexical error must reject the AST");
        }

        const auto result = syntax::parseFile(argv[1]);
        if (!result) {
            throw std::runtime_error(result.error);
        }
        if (argc == 2) {
            checkNestedControlFlow(*result.tree);
            return 0;
        }

        check(result.tree->items.size() == 1, "program item count");
        const auto& module = as<ast::Module>(result.tree->items.at(0));
        check(result.tree->items.at(0)->visibility == ast::Visibility::Public, "module visibility");
        checkDeclarations(module);
        checkBody(as<ast::Function>(module.items.at(5)));

        std::ostringstream output;
        ast::writeDot(output, *result.tree);
        const std::string dot = output.str();
        check(dot.find("digraph AST") == 0 && dot.find("label=\"tail\"") != std::string::npos &&
              dot.find("label=\"callee\"") != std::string::npos, "DOT must expose AST roles");
        check(dot.find("style=filled") != std::string::npos, "DOT nodes must have a visible fill");
        check(dot.find("label=\"Program\", shape=box, fillcolor=\"#cfe8ff\"") != std::string::npos &&
              dot.find("label=\"let mut local: i32;\", shape=box, fillcolor=\"#d9f2d0\"") != std::string::npos &&
              dot.find("label=\"i32\", shape=box, fillcolor=\"#ead9f5\"") != std::string::npos &&
              dot.find("label=\"input > 0\", shape=ellipse, fillcolor=\"#fff2cc\"") != std::string::npos,
              "DOT must distinguish structural nodes, statements, types and expressions");
        check(dot.find("label=\"pkg::call\", shape=ellipse, fillcolor=\"#cff3ef\"") != std::string::npos &&
              dot.find("label=\"1\", shape=ellipse, fillcolor=\"#ffdfa8\"") != std::string::npos &&
              dot.find("label=\"1.5;\", shape=ellipse, fillcolor=\"#ffdfa8\"") != std::string::npos &&
              dot.find("label=\"true\", shape=ellipse, fillcolor=\"#f9d6cf\"") != std::string::npos,
              "DOT must distinguish paths, numbers and booleans");
        check(dot.find("label=\"\\\"text\\\";\", shape=ellipse, fillcolor=\"#f4d7eb\"") != std::string::npos &&
              dot.find("label=\"r#\\\"raw\\\"#;\", shape=ellipse, fillcolor=\"#f4d7eb\"") != std::string::npos &&
              dot.find("label=\"'x';\", shape=ellipse, fillcolor=\"#f4d7eb\"") != std::string::npos,
              "DOT must color strings, raw strings and characters");
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
