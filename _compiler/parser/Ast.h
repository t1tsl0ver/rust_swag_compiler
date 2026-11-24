#pragma once

#include "Token.h"

#include <memory>
#include <optional>
#include <ostream>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace ast {

struct Expr;
struct Type;
struct Block;
struct Item;

struct TreeDeleter {
    void operator()(Expr* node) const noexcept;
    void operator()(Type* node) const noexcept;
    void operator()(Block* node) const noexcept;
    void operator()(Item* node) const noexcept;
};

template <typename Node>
using TreePtr = std::unique_ptr<Node, TreeDeleter>;

using ExprPtr = TreePtr<Expr>;
using TypePtr = TreePtr<Type>;
using BlockPtr = TreePtr<Block>;
using ItemPtr = TreePtr<Item>;
using ExprList = std::vector<ExprPtr>;
using ItemList = std::vector<ItemPtr>;

struct Name {
    std::string text;
    bool raw = false;
};

using Path = std::vector<Name>;

enum class Visibility { Inherited, Public, Parent, Current };

struct PathType { Path path; };
struct ArrayType { TypePtr element; ExprPtr length; };
struct ReferenceType { TypePtr target; bool mutableReference; };
struct ImplTraitType { TypePtr bound; };

struct Type {
    std::variant<PathType, ArrayType, ReferenceType, ImplTraitType> kind;
};

enum class BinaryOp {
    Add, Subtract, Multiply, Divide, Remainder,
    LogicalAnd, LogicalOr, Equal, NotEqual, Less, LessEqual, Greater, GreaterEqual,
};

enum class UnaryOp { Negate, Not, Dereference };

struct LiteralExpr { Token token; };
struct PathExpr { Path path; };
struct BinaryExpr { BinaryOp op; ExprPtr left; ExprPtr right; };
struct AssignExpr { ExprPtr target; ExprPtr value; };
struct UnaryExpr { UnaryOp op; ExprPtr operand; };
struct BorrowExpr { ExprPtr operand; bool mutableBorrow; };
struct TryExpr { ExprPtr operand; };
struct CastExpr { ExprPtr operand; TypePtr type; };
struct ParenthesizedExpr { ExprPtr inner; };
struct ArrayExpr { ExprList elements; };
struct RepeatArrayExpr { ExprPtr element; ExprPtr count; };
struct IndexExpr { ExprPtr receiver; ExprPtr index; };
struct FieldExpr { ExprPtr receiver; Name member; };
struct TupleFieldExpr { ExprPtr receiver; std::string index; };
struct CallExpr { ExprPtr callee; ExprList arguments; };
struct MethodCallExpr {
    ExprPtr receiver;
    Name method;
    ExprList arguments;
};
struct StructFieldValue {
    Name name;
    ExprPtr value;
};
using StructFieldValues = std::vector<StructFieldValue>;
struct StructExpr { Path path; StructFieldValues fields; };
struct RangeExpr { ExprPtr start; ExprPtr end; };
struct BlockExpr { BlockPtr block; };
struct IfExpr { ExprPtr condition; BlockPtr thenBlock; ExprPtr elseBranch; };
struct LoopExpr { BlockPtr body; };
struct WhileExpr { ExprPtr condition; BlockPtr body; };
struct ForExpr { Name variable; ExprPtr iterable; BlockPtr body; };
struct BreakExpr { ExprPtr value; };
struct ContinueExpr {};
struct ReturnExpr { ExprPtr value; };

struct Expr {
    std::variant<LiteralExpr, PathExpr, BinaryExpr, AssignExpr, UnaryExpr,
                 BorrowExpr, TryExpr, CastExpr, ParenthesizedExpr,
                 ArrayExpr, RepeatArrayExpr, IndexExpr, FieldExpr, TupleFieldExpr,
                 CallExpr, MethodCallExpr, StructExpr, RangeExpr, BlockExpr,
                 IfExpr, LoopExpr, WhileExpr, ForExpr, BreakExpr, ContinueExpr,
                 ReturnExpr> kind;
};

struct EmptyStmt {};
struct LetStmt {
    Name name;
    bool mutableBinding;
    TypePtr type;
    ExprPtr initializer;
};
struct ExprStmt { ExprPtr expression; bool hasSemicolon; };
struct ItemStmt { ItemPtr item; };

struct Stmt {
    std::variant<EmptyStmt, LetStmt, ExprStmt, ItemStmt> kind;
};

using StmtList = std::vector<Stmt>;

struct Block {
    StmtList statements;
    ExprPtr tail;
};

struct NamedParam { Name name; bool mutableBinding; TypePtr type; };
enum class ReceiverKind { Value, Reference, MutableReference };
struct Receiver { ReceiverKind kind; };
using Param = std::variant<NamedParam, Receiver>;
using ParamList = std::vector<Param>;

struct Function {
    Name name;
    ParamList parameters;
    TypePtr returnType;
    BlockPtr body;
};
struct Const { Name name; TypePtr type; ExprPtr initializer; };
struct Module { Name name; ItemList items; };

struct NamedField { Visibility visibility; Name name; TypePtr type; };
struct TupleField { Visibility visibility; TypePtr type; };
struct UnitFields {};
using NamedFields = std::vector<NamedField>;
using TupleFields = std::vector<TupleField>;
using Fields = std::variant<UnitFields, NamedFields, TupleFields>;

struct Struct { Name name; Fields fields; };
struct Variant {
    Name name;
    Fields fields;
    ExprPtr discriminant;
};
using VariantList = std::vector<Variant>;
struct Enum { Name name; VariantList variants; };
struct Trait { Name name; std::optional<Path> supertrait; ItemList items; };
struct Impl { std::optional<Path> trait; TypePtr target; ItemList items; };

struct Item {
    std::variant<Function, Const, Module, Struct, Enum, Trait, Impl> kind;
    Visibility visibility = Visibility::Inherited;
};

struct Program {
    ItemList items;
};

template <typename Kind>
ExprPtr expr(Kind kind)
{
    return ExprPtr(new Expr{std::move(kind)});
}

template <typename Kind>
TypePtr type(Kind kind)
{
    return TypePtr(new Type{std::move(kind)});
}

template <typename Kind>
ItemPtr item(Kind kind)
{
    return ItemPtr(new Item{std::move(kind)});
}

void writeDot(std::ostream& output, const Program& program);

}