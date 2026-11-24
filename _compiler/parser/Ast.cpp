#include "Ast.h"

#include <algorithm>
#include <cstddef>
#include <string_view>

namespace ast {
namespace {

using PendingDeletion = std::variant<Expr*, Type*, Block*, Item*>;
thread_local std::vector<PendingDeletion>* pendingDeletions = nullptr;

template <typename Node>
void deleteTree(Node* node) noexcept
{
    if (pendingDeletions) {
        try {
            pendingDeletions->push_back(node);
        } catch (...) {
            // Продолжаем освобождать узлы, даже если не удалось расширить список задач.
            delete node;
        }
        return;
    }

    // При удалении узла TreeDeleter добавляет его потомков в список задач.
    std::vector<PendingDeletion> pending;
    pendingDeletions = &pending;
    delete node;
    while (!pending.empty()) {
        const auto next = pending.back();
        pending.pop_back();
        std::visit([](auto* child) { delete child; }, next);
    }
    pendingDeletions = nullptr;
}

template <typename... Visitors>
struct Overloaded : Visitors... {
    using Visitors::operator()...;
};

template <typename... Visitors>
Overloaded(Visitors...) -> Overloaded<Visitors...>;

std::string escapeDot(std::string_view text)
{
    std::string escaped;
    for (const unsigned char character : text) {
        switch (character) {
        case '\\': escaped += "\\\\"; break;
        case '"': escaped += "\\\""; break;
        case '\n': escaped += "\\n"; break;
        case '\r': escaped += "\\r"; break;
        case '\t': escaped += "\\t"; break;
        default:
            if (character < 0x20 || character == 0x7f) {
                constexpr char hex[] = "0123456789abcdef";
                escaped += "\\\\x";
                escaped += hex[character >> 4];
                escaped += hex[character & 0x0f];
            } else {
                escaped += static_cast<char>(character);
            }
            break;
        }
    }
    return escaped;
}

std::string nameText(const Name& name)
{
    return name.raw ? "r#" + name.text : name.text;
}

std::string pathText(const Path& path)
{
    std::string text;
    for (const auto& segment : path) {
        if (!text.empty()) {
            text += "::";
        }
        text += nameText(segment);
    }
    return text;
}

std::string visibilityText(Visibility visibility)
{
    switch (visibility) {
    case Visibility::Public: return "pub ";
    case Visibility::Parent: return "pub(super) ";
    case Visibility::Current: return "pub(self) ";
    case Visibility::Inherited: return {};
    }
    return {};
}

std::string unaryText(UnaryOp op)
{
    switch (op) {
    case UnaryOp::Negate: return "-";
    case UnaryOp::Not: return "!";
    case UnaryOp::Dereference: return "*";
    }
    return {};
}

// Ограничиваем глубину и число элементов во фрагментах кода для подписей.
constexpr int previewDepth = 7;
constexpr std::size_t previewListSize = 4;

enum Precedence {
    Control, Assignment, Range, LogicalOr, LogicalAnd, Comparison,
    Sum, Product, Cast, Prefix, Postfix, Atom
};

struct ExpressionCode {
    std::string text;
    Precedence precedence = Atom;
};

std::string expressionText(const Expr& expression, int depth, int minimumPrecedence);

std::string expressionText(const ExprPtr& expression, int depth = previewDepth,
                           int minimumPrecedence = Control)
{
    return expression ? expressionText(*expression, depth, minimumPrecedence) : std::string{};
}

template <typename List, typename Format>
std::string listText(const List& list, Format format)
{
    std::string text;
    const std::size_t count = std::min(list.size(), previewListSize);
    for (std::size_t index = 0; index < count; ++index) {
        if (index != 0) {
            text += ", ";
        }
        text += format(list[index]);
    }
    if (list.size() > count) {
        text += ", ...";
    }
    return text;
}

std::string expressionsText(const ExprList& list, int depth)
{
    return listText(list, [depth](const auto& expression) { return expressionText(expression, depth); });
}

std::string typeText(const TypePtr& type, int depth = previewDepth);

std::string typeCode(const PathType& type, int) { return pathText(type.path); }

std::string typeCode(const ArrayType& type, int depth)
{
    return "[" + typeText(type.element, depth) + "; " + expressionText(type.length, depth) + "]";
}

std::string typeCode(const ReferenceType& type, int depth)
{
    return (type.mutableReference ? "&mut " : "&") + typeText(type.target, depth);
}

std::string typeCode(const ImplTraitType& type, int depth)
{
    return "impl " + typeText(type.bound, depth);
}

std::string typeText(const TypePtr& type, int depth)
{
    if (!type) {
        return {};
    }
    if (depth == 0) {
        return "...";
    }
    return std::visit([depth](const auto& kind) { return typeCode(kind, depth - 1); }, type->kind);
}

std::string parameterText(Receiver receiver)
{
    switch (receiver.kind) {
    case ReceiverKind::Reference: return "&self";
    case ReceiverKind::MutableReference: return "&mut self";
    case ReceiverKind::Value: return "self";
    }
    return "self";
}

std::string parameterText(const NamedParam& parameter)
{
    return (parameter.mutableBinding ? "mut " : "") + nameText(parameter.name) + ": " + typeText(parameter.type);
}

std::string blockText(const Block& block)
{
    return block.statements.empty() && !block.tail ? "{}" : "{ ... }";
}

struct BinaryInfo {
    const char* text;
    Precedence precedence;
};

BinaryInfo binaryInfo(BinaryOp op)
{
    switch (op) {
    case BinaryOp::Add: return {"+", Sum};
    case BinaryOp::Subtract: return {"-", Sum};
    case BinaryOp::Multiply: return {"*", Product};
    case BinaryOp::Divide: return {"/", Product};
    case BinaryOp::Remainder: return {"%", Product};
    case BinaryOp::LogicalAnd: return {"&&", LogicalAnd};
    case BinaryOp::LogicalOr: return {"||", LogicalOr};
    case BinaryOp::Equal: return {"==", Comparison};
    case BinaryOp::NotEqual: return {"!=", Comparison};
    case BinaryOp::Less: return {"<", Comparison};
    case BinaryOp::LessEqual: return {"<=", Comparison};
    case BinaryOp::Greater: return {">", Comparison};
    case BinaryOp::GreaterEqual: return {">=", Comparison};
    }
    return {"", Comparison};
}

ExpressionCode expressionCode(const LiteralExpr& expression, int) { return {expression.token.spelling}; }
ExpressionCode expressionCode(const PathExpr& expression, int) { return {pathText(expression.path)}; }

ExpressionCode expressionCode(const BinaryExpr& expression, int depth)
{
    const auto [text, precedence] = binaryInfo(expression.op);
    const int leftPrecedence = precedence == Comparison ? precedence + 1 : precedence;
    return {expressionText(expression.left, depth, leftPrecedence) + " " + text + " " +
                expressionText(expression.right, depth, precedence + 1), precedence};
}

ExpressionCode expressionCode(const AssignExpr& expression, int depth)
{
    return {expressionText(expression.target, depth, Assignment + 1) + " = " +
                expressionText(expression.value, depth), Assignment};
}

ExpressionCode expressionCode(const UnaryExpr& expression, int depth)
{
    return {unaryText(expression.op) + expressionText(expression.operand, depth, Prefix), Prefix};
}

ExpressionCode expressionCode(const BorrowExpr& expression, int depth)
{
    const auto operand = expressionText(expression.operand, depth, Prefix);
    if (expression.mutableBorrow) {
        return {"&mut " + operand, Prefix};
    }
    return {(operand.rfind('&', 0) == 0 ? "& " : "&") + operand, Prefix};
}

ExpressionCode expressionCode(const TryExpr& expression, int depth)
{
    return {expressionText(expression.operand, depth, Postfix) + "?", Postfix};
}

ExpressionCode expressionCode(const CastExpr& expression, int depth)
{
    return {expressionText(expression.operand, depth, Cast) + " as " + typeText(expression.type, depth), Cast};
}

ExpressionCode expressionCode(const ParenthesizedExpr& expression, int depth)
{
    return {"(" + expressionText(expression.inner, depth) + ")"};
}

ExpressionCode expressionCode(const ArrayExpr& expression, int depth)
{
    return {"[" + expressionsText(expression.elements, depth) + "]"};
}

ExpressionCode expressionCode(const RepeatArrayExpr& expression, int depth)
{
    return {"[" + expressionText(expression.element, depth) + "; " + expressionText(expression.count, depth) + "]"};
}

ExpressionCode expressionCode(const IndexExpr& expression, int depth)
{
    return {expressionText(expression.receiver, depth, Postfix) + "[" + expressionText(expression.index, depth) +
                "]", Postfix};
}

ExpressionCode expressionCode(const FieldExpr& expression, int depth)
{
    return {expressionText(expression.receiver, depth, Postfix) + "." + nameText(expression.member), Postfix};
}

ExpressionCode expressionCode(const TupleFieldExpr& expression, int depth)
{
    return {expressionText(expression.receiver, depth, Postfix) + "." + expression.index, Postfix};
}

ExpressionCode expressionCode(const CallExpr& expression, int depth)
{
    return {expressionText(expression.callee, depth, Postfix) + "(" + expressionsText(expression.arguments, depth) +
                ")", Postfix};
}

ExpressionCode expressionCode(const MethodCallExpr& expression, int depth)
{
    return {expressionText(expression.receiver, depth, Postfix) + "." + nameText(expression.method) + "(" +
                expressionsText(expression.arguments, depth) + ")", Postfix};
}

std::string structFieldText(const StructFieldValue& field, int depth)
{
    return nameText(field.name) + ": " + expressionText(field.value, depth);
}

ExpressionCode expressionCode(const StructExpr& expression, int depth)
{
    const auto fields = listText(expression.fields, [depth](const StructFieldValue& field) {
        return structFieldText(field, depth);
    });
    return {pathText(expression.path) + (fields.empty() ? " {}" : " { " + fields + " }")};
}

ExpressionCode expressionCode(const RangeExpr& expression, int depth)
{
    return {expressionText(expression.start, depth, Range + 1) + ".." + expressionText(expression.end, depth, Range + 1),
            Range};
}

ExpressionCode expressionCode(const BlockExpr& expression, int) { return {blockText(*expression.block)}; }

ExpressionCode expressionCode(const IfExpr& expression, int depth)
{
    return {"if " + expressionText(expression.condition, depth) + " " + blockText(*expression.thenBlock)};
}

ExpressionCode expressionCode(const LoopExpr& expression, int) { return {"loop " + blockText(*expression.body)}; }

ExpressionCode expressionCode(const WhileExpr& expression, int depth)
{
    return {"while " + expressionText(expression.condition, depth) + " " + blockText(*expression.body)};
}

ExpressionCode expressionCode(const ForExpr& expression, int depth)
{
    return {"for " + nameText(expression.variable) + " in " + expressionText(expression.iterable, depth) +
                " " + blockText(*expression.body)};
}

ExpressionCode expressionCode(const BreakExpr& expression, int depth)
{
    return {expression.value ? "break " + expressionText(expression.value, depth) : "break", Control};
}

ExpressionCode expressionCode(ContinueExpr, int) { return {"continue", Control}; }

ExpressionCode expressionCode(const ReturnExpr& expression, int depth)
{
    return {expression.value ? "return " + expressionText(expression.value, depth) : "return", Control};
}

std::string expressionText(const Expr& expression, int depth, int minimumPrecedence)
{
    if (depth == 0) {
        return "...";
    }
    auto code = std::visit([depth](const auto& kind) { return expressionCode(kind, depth - 1); }, expression.kind);
    if (code.precedence < minimumPrecedence) {
        return "(" + code.text + ")";
    }
    return std::move(code.text);
}

class DotWriter {
public:
    explicit DotWriter(std::ostream& stream) : output(stream) {}

    void program(const Program& program)
    {
        output << "digraph AST {\n"
               << "  node [fontname=\"monospace\"];\n";
        const Id id = node("Program");
        children(id, program.items, "item");
        std::reverse(pending.begin(), pending.end());
        while (!pending.empty()) {
            const auto task = pending.back();
            pending.pop_back();
            std::visit(Overloaded{
                [this](const Child& child) { emitChild(child); },
                [this](const Link& link) { edge(link.parent, link.child, link.role, link.position); },
            }, task);
        }
        output << "}\n";
    }

private:
    using Id = std::size_t;
    using Node = std::variant<const Item*, const Block*, const Variant*, const Fields*,
                              const NamedField*, const TupleField*, const Param*, const Type*,
                              const Stmt*, const Expr*, const StructFieldValue*>;

    struct Child {
        Node value;
        Id parent;
        std::string_view role;
        std::size_t position;
    };

    struct Link {
        Id parent;
        Id child;
        std::string_view role;
        std::size_t position;
    };

    std::ostream& output;
    Id nextId = 0;
    std::vector<std::variant<Child, Link>> pending;

    void emitChild(const Child& child)
    {
        const auto firstChild = pending.size();
        const Id id = std::visit(Overloaded{
            [this](const Item* value) { return emitItem(*value); },
            [this](const Block* value) { return emitBlock(*value); },
            [this](const Variant* value) { return emitVariant(*value); },
            [this](const Fields* value) { return emitFields(*value); },
            [this](const NamedField* value) { return emitNamedField(*value); },
            [this](const TupleField* value) { return emitTupleField(*value); },
            [this](const Param* value) { return emitParameter(*value); },
            [this](const Type* value) { return emitType(*value); },
            [this](const Stmt* value) { return emitStatement(*value); },
            [this](const Expr* value) { return emitExpression(*value); },
            [this](const StructFieldValue* value) { return emitStructField(*value); },
        }, child.value);

        // Обходим потомков в порядке исходника. Входящее ребро выводим после поддерева.
        const auto first = pending.begin() + firstChild;
        std::reverse(first, pending.end());
        pending.insert(first, Link{child.parent, id, child.role, child.position});
    }

    Id node(std::string_view label)
    {
        constexpr std::size_t labelLimit = 110;
        const bool shortened = label.size() > labelLimit;
        const Id id = nextId++;
        output << "  n" << id << " [label=\"" << escapeDot(label.substr(0, shortened ? labelLimit - 3 : labelLimit))
               << (shortened ? "..." : "") << "\"];\n";
        return id;
    }

    void edge(Id parent, Id child, std::string_view role, std::size_t position = 0)
    {
        output << "  n" << parent << " -> n" << child << " [label=\"" << role;
        if (position != 0) {
            output << ' ' << position;
        }
        output << "\"];\n";
    }

    template <typename T>
    void child(Id parent, const T& value, std::string_view role, std::size_t position = 0)
    {
        pending.push_back(Child{&value, parent, role, position});
    }

    template <typename T, typename Deleter>
    void child(Id parent, const std::unique_ptr<T, Deleter>& value, std::string_view role, std::size_t position = 0)
    {
        if (value) {
            child(parent, *value, role, position);
        }
    }

    template <typename List>
    void children(Id parent, const List& values, std::string_view role)
    {
        for (const auto& value : values) {
            child(parent, value, role);
        }
    }

    template <typename List>
    void numberedChildren(Id parent, const List& values, std::string_view role)
    {
        for (std::size_t index = 0; index < values.size(); ++index) {
            child(parent, values[index], role, index + 1);
        }
    }

    void blockChildren(Id id, const Block& block)
    {
        children(id, block.statements, "statement");
        child(id, block.tail, "tail");
    }

    Id emitBlock(const Block& block)
    {
        const Id id = node(blockText(block));
        blockChildren(id, block);
        return id;
    }

    Id emitItem(const Item& item)
    {
        const auto visibility = item.visibility;
        return std::visit(Overloaded{
            [&](const Function& value) { return emitFunction(value, visibility); },
            [&](const Const& value) { return emitConst(value, visibility); },
            [&](const Module& value) { return emitModule(value, visibility); },
            [&](const Struct& value) { return emitStruct(value, visibility); },
            [&](const Enum& value) { return emitEnum(value, visibility); },
            [&](const Trait& value) { return emitTrait(value, visibility); },
            [&](const Impl& value) { return emitImpl(value, visibility); },
        }, item.kind);
    }

    Id emitFunction(const Function& function, Visibility visibility)
    {
        const auto parameters = listText(function.parameters, [](const Param& parameter) {
            return std::visit([](const auto& kind) { return parameterText(kind); }, parameter);
        });
        std::string signature = visibilityText(visibility) + "fn " + nameText(function.name) + "(" + parameters + ")";
        if (function.returnType) {
            signature += " -> " + typeText(function.returnType);
        }
        if (!function.body) {
            signature += ';';
        }
        const Id id = node(signature);
        numberedChildren(id, function.parameters, "parameter");
        child(id, function.returnType, "return type");
        child(id, function.body, "body");
        return id;
    }

    Id emitConst(const Const& constant, Visibility visibility)
    {
        auto label = visibilityText(visibility) + "const " + nameText(constant.name) + ": " + typeText(constant.type);
        if (constant.initializer) {
            label += " = " + expressionText(constant.initializer);
        }
        const Id id = node(label + ";");
        child(id, constant.type, "type");
        child(id, constant.initializer, "initializer");
        return id;
    }

    Id emitModule(const Module& module, Visibility visibility)
    {
        const Id id = node(visibilityText(visibility) + "mod " + nameText(module.name));
        children(id, module.items, "item");
        return id;
    }

    Id emitStruct(const Struct& structure, Visibility visibility)
    {
        const Id id = node(visibilityText(visibility) + "struct " + nameText(structure.name));
        child(id, structure.fields, "fields");
        return id;
    }

    Id emitEnum(const Enum& enumeration, Visibility visibility)
    {
        const Id id = node(visibilityText(visibility) + "enum " + nameText(enumeration.name));
        children(id, enumeration.variants, "variant");
        return id;
    }

    Id emitTrait(const Trait& trait, Visibility visibility)
    {
        auto label = visibilityText(visibility) + "trait " + nameText(trait.name);
        const auto supertrait = trait.supertrait ? pathText(*trait.supertrait) : std::string{};
        if (trait.supertrait) {
            label += ": " + supertrait;
        }
        const Id id = node(label);
        if (trait.supertrait) {
            edge(id, node(supertrait), "supertrait");
        }
        children(id, trait.items, "associated item");
        return id;
    }

    Id emitImpl(const Impl& implementation, Visibility visibility)
    {
        auto label = visibilityText(visibility) + "impl ";
        const auto trait = implementation.trait ? pathText(*implementation.trait) : std::string{};
        if (implementation.trait) {
            label += trait + " for ";
        }
        const Id id = node(label + typeText(implementation.target));
        if (implementation.trait) {
            edge(id, node(trait), "trait");
        }
        child(id, implementation.target, "target");
        children(id, implementation.items, "associated item");
        return id;
    }

    Id emitVariant(const Variant& variant)
    {
        auto label = nameText(variant.name);
        if (variant.discriminant) {
            label += " = " + expressionText(variant.discriminant);
        }
        const Id id = node(label);
        child(id, variant.fields, "fields");
        child(id, variant.discriminant, "discriminant");
        return id;
    }

    Id emitFields(const Fields& fields)
    {
        return std::visit(Overloaded{
            [this](UnitFields) { return node("Unit"); },
            [this](const NamedFields& value) { return emitFieldList(value, "Named fields"); },
            [this](const TupleFields& value) { return emitFieldList(value, "Tuple fields"); },
        }, fields);
    }

    template <typename List>
    Id emitFieldList(const List& fields, std::string_view label)
    {
        const Id id = node(label);
        children(id, fields, "field");
        return id;
    }

    Id emitNamedField(const NamedField& field)
    {
        const Id id = node(visibilityText(field.visibility) + nameText(field.name) + ": " + typeText(field.type));
        child(id, field.type, "type");
        return id;
    }

    Id emitTupleField(const TupleField& field)
    {
        const Id id = node(visibilityText(field.visibility) + typeText(field.type));
        child(id, field.type, "type");
        return id;
    }

    Id emitParameter(const Param& parameter)
    {
        return std::visit(Overloaded{
            [this](Receiver value) { return node(parameterText(value)); },
            [this](const NamedParam& value) {
                const Id id = node(parameterText(value));
                child(id, value.type, "type");
                return id;
            },
        }, parameter);
    }

    Id emitType(const Type& type)
    {
        return std::visit([this](const auto& kind) {
            const Id id = node(typeCode(kind, previewDepth - 1));
            typeChildren(id, kind);
            return id;
        }, type.kind);
    }

    void typeChildren(Id, const PathType&) {}

    void typeChildren(Id id, const ArrayType& type)
    {
        child(id, type.element, "element type");
        child(id, type.length, "length");
    }

    void typeChildren(Id id, const ReferenceType& type)
    {
        child(id, type.target, "target type");
    }

    void typeChildren(Id id, const ImplTraitType& type)
    {
        child(id, type.bound, "bound");
    }

    Id emitStatement(const Stmt& statement)
    {
        return std::visit(Overloaded{
            [this](EmptyStmt) { return node(";"); },
            [this](const LetStmt& value) { return emitLet(value); },
            [this](const ExprStmt& value) { return emitExpression(*value.expression, value.hasSemicolon ? ";" : ""); },
            [this](const ItemStmt& value) { return emitItem(*value.item); },
        }, statement.kind);
    }

    Id emitLet(const LetStmt& statement)
    {
        const std::string prefix = statement.mutableBinding ? "let mut " : "let ";
        auto label = prefix + nameText(statement.name);
        if (statement.type) {
            label += ": " + typeText(statement.type);
        }
        if (statement.initializer) {
            label += " = " + expressionText(statement.initializer);
        }
        const Id id = node(label + ";");
        child(id, statement.type, "type");
        child(id, statement.initializer, "initializer");
        return id;
    }

    Id emitExpression(const Expr& expression, std::string_view suffix = {})
    {
        return std::visit([&](const auto& kind) {
            auto label = expressionCode(kind, previewDepth - 1).text;
            label += suffix;
            const Id id = node(label);
            expressionChildren(id, kind);
            return id;
        }, expression.kind);
    }

    void expressionChildren(Id, const LiteralExpr&) {}
    void expressionChildren(Id, const PathExpr&) {}

    void expressionChildren(Id id, const BinaryExpr& expression)
    {
        child(id, expression.left, "left");
        child(id, expression.right, "right");
    }

    void expressionChildren(Id id, const AssignExpr& expression)
    {
        child(id, expression.target, "target");
        child(id, expression.value, "value");
    }

    void expressionChildren(Id id, const UnaryExpr& expression)
    {
        child(id, expression.operand, "operand");
    }

    void expressionChildren(Id id, const BorrowExpr& expression)
    {
        child(id, expression.operand, "operand");
    }

    void expressionChildren(Id id, const TryExpr& expression)
    {
        child(id, expression.operand, "operand");
    }

    void expressionChildren(Id id, const CastExpr& expression)
    {
        child(id, expression.operand, "operand");
        child(id, expression.type, "type");
    }

    void expressionChildren(Id id, const ParenthesizedExpr& expression)
    {
        child(id, expression.inner, "inner");
    }

    void expressionChildren(Id id, const ArrayExpr& expression)
    {
        children(id, expression.elements, "element");
    }

    void expressionChildren(Id id, const RepeatArrayExpr& expression)
    {
        child(id, expression.element, "element");
        child(id, expression.count, "count");
    }

    void expressionChildren(Id id, const IndexExpr& expression)
    {
        child(id, expression.receiver, "receiver");
        child(id, expression.index, "index");
    }

    void expressionChildren(Id id, const FieldExpr& expression)
    {
        child(id, expression.receiver, "receiver");
    }

    void expressionChildren(Id id, const TupleFieldExpr& expression)
    {
        child(id, expression.receiver, "receiver");
    }

    void expressionChildren(Id id, const CallExpr& expression)
    {
        child(id, expression.callee, "callee");
        numberedChildren(id, expression.arguments, "argument");
    }

    void expressionChildren(Id id, const MethodCallExpr& expression)
    {
        child(id, expression.receiver, "receiver");
        numberedChildren(id, expression.arguments, "argument");
    }

    void expressionChildren(Id id, const StructExpr& expression)
    {
        children(id, expression.fields, "field");
    }

    Id emitStructField(const StructFieldValue& field)
    {
        const Id id = node(structFieldText(field, previewDepth));
        child(id, field.value, "value");
        return id;
    }

    void expressionChildren(Id id, const RangeExpr& expression)
    {
        child(id, expression.start, "start");
        child(id, expression.end, "end");
    }

    void expressionChildren(Id id, const BlockExpr& expression) { blockChildren(id, *expression.block); }

    void expressionChildren(Id id, const IfExpr& expression)
    {
        child(id, expression.condition, "condition");
        child(id, expression.thenBlock, "then");
        child(id, expression.elseBranch, "else");
    }

    void expressionChildren(Id id, const LoopExpr& expression)
    {
        child(id, expression.body, "body");
    }

    void expressionChildren(Id id, const WhileExpr& expression)
    {
        child(id, expression.condition, "condition");
        child(id, expression.body, "body");
    }

    void expressionChildren(Id id, const ForExpr& expression)
    {
        child(id, expression.iterable, "iterable");
        child(id, expression.body, "body");
    }

    void expressionChildren(Id id, const BreakExpr& expression)
    {
        child(id, expression.value, "value");
    }

    void expressionChildren(Id, ContinueExpr) {}

    void expressionChildren(Id id, const ReturnExpr& expression)
    {
        child(id, expression.value, "value");
    }
};

}

void TreeDeleter::operator()(Expr* node) const noexcept { deleteTree(node); }
void TreeDeleter::operator()(Type* node) const noexcept { deleteTree(node); }
void TreeDeleter::operator()(Block* node) const noexcept { deleteTree(node); }
void TreeDeleter::operator()(Item* node) const noexcept { deleteTree(node); }

void writeDot(std::ostream& output, const Program& program)
{
    DotWriter(output).program(program);
}

}