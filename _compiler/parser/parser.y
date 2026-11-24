%define api.pure full
%define parse.error detailed
%define parse.lac full

%code requires {
#include "Ast.h"

class LexerContext;
namespace syntax { struct ParseResult; }
}

%parse-param { LexerContext& lexer }
%parse-param { syntax::ParseResult& result }
%lex-param { LexerContext& lexer }

%code {
#include "Parser.h"

#include <type_traits>

int yylex(YYSTYPE* value, LexerContext& lexer);
void yyerror(LexerContext& lexer, syntax::ParseResult& result, const char* message);

namespace {

// Bison хранит владеющие указатели. При свёртке владение передаётся AST или результату правила.
template <typename Value>
auto own(Value* value)
{
    if constexpr (std::is_invocable_v<ast::TreeDeleter, Value*>) {
        return ast::TreePtr<Value>(value);
    } else {
        return std::unique_ptr<Value>(value);
    }
}

template <typename Value>
Value take(Value* value)
{
    auto owned = own(value);
    return std::move(*owned);
}

template <typename List>
List* append(List* list, typename List::value_type value)
{
    auto owned = own(list);
    owned->push_back(std::move(value));
    return owned.release();
}

template <typename List>
List* one(typename List::value_type value)
{
    return append(new List, std::move(value));
}

ast::TypePtr maybeImplTrait(ast::TypePtr type, bool isImpl)
{
    if (isImpl) {
        return ast::type(ast::ImplTraitType{std::move(type)});
    }
    return type;
}

ast::BlockPtr block(ast::StmtList statements = {}, ast::ExprPtr tail = {})
{
    // Последнее выражение с блоком без точки с запятой становится завершающим выражением блока.
    if (!tail && !statements.empty()) {
        auto* last = std::get_if<ast::ExprStmt>(&statements.back().kind);
        if (last && !last->hasSemicolon) {
            tail = std::move(last->expression);
            statements.pop_back();
        }
    }
    return ast::BlockPtr(new ast::Block{std::move(statements), std::move(tail)});
}

}
}

%union {
    ast::Name* name;
    Token* literal;
    ast::ItemList* items;
    ast::Item* item;
    ast::ParamList* parameters;
    ast::Param* parameter;
    ast::Type* type;
    ast::NamedFields* namedFields;
    ast::NamedField* namedField;
    ast::TupleFields* tupleFields;
    ast::TupleField* tupleField;
    ast::VariantList* variants;
    ast::Variant* variant;
    ast::StmtList* statements;
    ast::Stmt* statement;
    ast::ExprList* expressions;
    ast::Expr* expression;
    ast::Block* block;
    ast::Path* path;
    ast::StructFieldValues* fieldValues;
    ast::StructFieldValue* fieldValue;
    ast::Visibility visibility;
    bool flag;
}

%destructor { delete $$; } <name> <literal> <item> <type> <expression> <block>
%destructor { delete $$; } <items> <parameters> <parameter> <namedFields> <namedField>
%destructor { delete $$; } <tupleFields> <tupleField> <variants> <variant>
%destructor { delete $$; } <statements> <statement> <expressions> <path> <fieldValues> <fieldValue>

%type <items> ItemListEmpty ItemList AssociatedItemListEmpty AssociatedItemList
%type <item> Item SimpleItem FuncStmt DecFuncStmt ImplFuncStmt StructStmt StructStruct
%type <item> TupleStruct EnumStmt ImplStmt AssociatedItem TraitStmt ConstStmt ModuleStmt
%type <visibility> Visibility_opt Visibility
%type <parameters> FuncParamListEmpty FuncParamList
%type <parameter> SelfParam FuncParam
%type <flag> MutOpt ImplOpt
%type <type> ReturnType ParamType Type
%type <namedFields> StructFieldListEmpty StructFieldList
%type <namedField> StructField
%type <tupleFields> TupleFieldListEmpty TupleFieldList
%type <tupleField> TupleField
%type <variants> EnumItemListEmpty EnumItemList
%type <variant> EnumItem
%type <statements> StmtList
%type <statement> Stmt LetStmt ExprStmt
%type <expressions> ExprListEmpty ExprList
%type <expression> Expr Literal ExprWithoutBlock ExprNoStruct StructExpr ExprWithBlock
%type <expression> LoopExpr InfiniteLoopExpr PredicateLoopExpr IteratorLoopExpr IfExpr
%type <block> BlockExpr
%type <path> PathPrefix TypePath Path
%type <fieldValues> StructExprFieldListEmpty StructExprFieldList
%type <fieldValue> StructExprField

/* ТОКЕНЫ */

/* --- Ключевые слова --- */
%token AS BREAK CONST CONTINUE CRATE ELSE ENUM FN FOR IF IMPL IN
%token LET LOOP MOD MUT PUB RETURN SELF_TYPE SELF_VALUE STRUCT SUPER TRAIT WHILE

/* --- Идентификаторы и литералы --- */
%token <name> ID
%token <literal> INTEGER_LITERAL FLOAT_LITERAL BOOLEAN_LITERAL
%token <literal> STRING_LITERAL RAW_STRING_LITERAL CHAR_LITERAL

/* --- Пунктуация и операторы: символические имена + читаемые алиасы --- */
%token LEFT_PAREN     "("
%token RIGHT_PAREN    ")"
%token LEFT_BRACE     "{"
%token RIGHT_BRACE    "}"
%token LEFT_BRACKET   "["
%token RIGHT_BRACKET  "]"
%token SEMICOLON      ";"
%token COMMA          ","
%token COLON          ":"
%token PATH_SEPARATOR "::"
%token DOT            "."
%token QUESTION       "?"
%token ASSIGN         "="
%token PLUS           "+"
%token MINUS          "-"
%token STAR           "*"
%token SLASH          "/"
%token REMAINDER      "%"
%token BANG           "!"
%token AMPERSAND      "&"
%token LESS           "<"
%token GREATER        ">"
%token EQUAL_EQUAL    "=="
%token NOT_EQUAL      "!="
%token LESS_EQUAL     "<="
%token GREATER_EQUAL  ">="
%token LOGICAL_AND    "&&"
%token LOGICAL_OR     "||"
%token RIGHT_ARROW    "->"
%token RANGE          ".."

/* --- Вспомогательные маркеры приоритета --- */
%token UMINUS USTAR

/* ПРИОРИТЕТЫ */

%nonassoc BREAK RETURN
%nonassoc "{" "}"
%right ":"
%right "="
%nonassoc ".."
%left "||"
%left "&&"
%left "<" ">" "==" "!=" "<=" ">="
%left "+" "-"
%left "*" "/" "%"
%left AS
%left "!" "&" MUT UMINUS USTAR
%nonassoc "?"
%left "." "[" "::"
%nonassoc "(" ")"

%start Program

%%

/* ПРОГРАММА */

Program : ItemListEmpty { result.tree = std::make_unique<ast::Program>(ast::Program{take($1)}); }

/* ОПЕРАТОРЫ */

StmtList : Stmt { $$ = one<ast::StmtList>(take($1)); }
         | StmtList Stmt { $$ = append($1, take($2)); }

Stmt : ";" { $$ = new ast::Stmt{ast::EmptyStmt{}}; }
     | LetStmt { $$ = $1; }
     | ExprStmt { $$ = $1; }
     | ConstStmt { $$ = new ast::Stmt{ast::ItemStmt{own($1)}}; }

ItemListEmpty : /* пусто */ { $$ = new ast::ItemList{}; }
              | ItemList { $$ = $1; }

ItemList : Item { $$ = one<ast::ItemList>(own($1)); }
         | ItemList Item { $$ = append($1, own($2)); }

/* [замечание 1] Visibility_opt объединяет пустой и Visibility варианты */
Visibility_opt : /* пусто */ { $$ = ast::Visibility::Inherited; }
               | Visibility { $$ = $1; }

Item : Visibility_opt SimpleItem { $$ = $2; $$->visibility = $1; }

SimpleItem : FuncStmt { $$ = $1; }
           | StructStmt { $$ = $1; }
           | EnumStmt { $$ = $1; }
           | ImplStmt { $$ = $1; }
           | TraitStmt { $$ = $1; }
           | ConstStmt { $$ = $1; }
           | ModuleStmt { $$ = $1; }

/* ФУНКЦИИ */

FuncStmt : DecFuncStmt { $$ = $1; }
         | ImplFuncStmt { $$ = $1; }

DecFuncStmt : FN ID "(" FuncParamListEmpty ")" ";" { $$ = ast::item(ast::Function{take($2), take($4), {}, {}}).release(); }
            | FN ID "(" FuncParamListEmpty ")" "->" ReturnType ";" { $$ = ast::item(ast::Function{take($2), take($4), own($7), {}}).release(); }

ImplFuncStmt : FN ID "(" FuncParamListEmpty ")" BlockExpr { $$ = ast::item(ast::Function{take($2), take($4), {}, own($6)}).release(); }
             | FN ID "(" FuncParamListEmpty ")" "->" ReturnType BlockExpr { $$ = ast::item(ast::Function{take($2), take($4), own($7), own($8)}).release(); }

/* [замечание 1] ReturnType объединяет Type и IMPL Type */
ReturnType : Type { $$ = $1; }
           | IMPL Type { $$ = ast::type(ast::ImplTraitType{own($2)}).release(); }

FuncParamListEmpty : /* пусто */ { $$ = new ast::ParamList{}; }
                   | FuncParamList { $$ = $1; }

/* [замечание 1] self-параметры вынесены в SelfParam */
FuncParamList : SelfParam { $$ = one<ast::ParamList>(take($1)); }
              | FuncParam { $$ = one<ast::ParamList>(take($1)); }
              | FuncParamList "," FuncParam { $$ = append($1, take($3)); }

SelfParam : SELF_VALUE { $$ = new ast::Param{ast::Receiver{ast::ReceiverKind::Value}}; }
          | "&" SELF_VALUE { $$ = new ast::Param{ast::Receiver{ast::ReceiverKind::Reference}}; }
          | "&" MUT SELF_VALUE { $$ = new ast::Param{ast::Receiver{ast::ReceiverKind::MutableReference}}; }

/* [замечание 1] FuncParam: выделены нетерминалы для модификаторов типа */
FuncParam : MutOpt ID ":" ParamType { $$ = new ast::Param{ast::NamedParam{take($2), $1, own($4)}}; }

MutOpt : /* пусто */ { $$ = false; }
       | MUT { $$ = true; }

/* [замечание 1] ParamType объединяет все варианты типов параметра */
ParamType : ImplOpt Type { $$ = maybeImplTrait(own($2), $1).release(); }
          | "&" ImplOpt Type {
                $$ = ast::type(ast::ReferenceType{maybeImplTrait(own($3), $2), false}).release();
            }
          | "&" MUT ImplOpt Type {
                $$ = ast::type(ast::ReferenceType{maybeImplTrait(own($4), $3), true}).release();
            }

ImplOpt : /* пусто */ { $$ = false; }
        | IMPL { $$ = true; }

/* СТРУКТУРЫ */

StructStmt : StructStruct { $$ = $1; }
           | TupleStruct { $$ = $1; }

StructStruct : STRUCT ID "{" StructFieldListEmpty "}" { $$ = ast::item(ast::Struct{take($2), take($4)}).release(); }
             | STRUCT ID ";" { $$ = ast::item(ast::Struct{take($2), ast::UnitFields{}}).release(); }

StructFieldListEmpty : /* пусто */ { $$ = new ast::NamedFields{}; }
                     | StructFieldList { $$ = $1; }
                     | StructFieldList "," { $$ = $1; }

StructFieldList : StructField { $$ = one<ast::NamedFields>(take($1)); }
                | StructFieldList "," StructField { $$ = append($1, take($3)); }

StructField : Visibility_opt ID ":" Type { $$ = new ast::NamedField{$1, take($2), own($4)}; }

TupleStruct : STRUCT ID "(" TupleFieldListEmpty ")" { $$ = ast::item(ast::Struct{take($2), take($4)}).release(); }

TupleFieldListEmpty : /* пусто */ { $$ = new ast::TupleFields{}; }
                    | TupleFieldList { $$ = $1; }
                    | TupleFieldList "," { $$ = $1; }

TupleFieldList : TupleField { $$ = one<ast::TupleFields>(take($1)); }
               | TupleFieldList "," TupleField { $$ = append($1, take($3)); }

TupleField : Visibility_opt Type { $$ = new ast::TupleField{$1, own($2)}; }

/* ПЕРЕЧИСЛЕНИЯ */

EnumStmt : ENUM ID "{" EnumItemListEmpty "}" { $$ = ast::item(ast::Enum{take($2), take($4)}).release(); }

EnumItemListEmpty : /* пусто */ { $$ = new ast::VariantList{}; }
                  | EnumItemList { $$ = $1; }
                  | EnumItemList "," { $$ = $1; }

EnumItemList : EnumItem { $$ = one<ast::VariantList>(take($1)); }
             | EnumItemList "," EnumItem { $$ = append($1, take($3)); }


EnumItem : ID { $$ = new ast::Variant{take($1), ast::UnitFields{}, {}}; }
         | ID "=" Expr { $$ = new ast::Variant{take($1), ast::UnitFields{}, own($3)}; }
         | ID "{" StructFieldListEmpty "}" { $$ = new ast::Variant{take($1), take($3), {}}; }

/* РЕАЛИЗАЦИИ */

ImplStmt : IMPL Type "{" AssociatedItemListEmpty "}" { $$ = ast::item(ast::Impl{{}, own($2), take($4)}).release(); }
         | IMPL TypePath FOR Type "{" AssociatedItemListEmpty "}" { $$ = ast::item(ast::Impl{take($2), own($4), take($6)}).release(); }

AssociatedItemListEmpty : /* пусто */ { $$ = new ast::ItemList{}; }
                        | AssociatedItemList { $$ = $1; }

AssociatedItemList : AssociatedItem { $$ = one<ast::ItemList>(own($1)); }
                   | AssociatedItemList AssociatedItem { $$ = append($1, own($2)); }

AssociatedItem : Visibility_opt FuncStmt { $$ = $2; $$->visibility = $1; }
               | Visibility_opt ConstStmt { $$ = $2; $$->visibility = $1; }

/* ТРЕЙТЫ */

TraitStmt : TRAIT ID "{" AssociatedItemListEmpty "}" { $$ = ast::item(ast::Trait{take($2), {}, take($4)}).release(); }
          | TRAIT ID ":" ID "{" AssociatedItemListEmpty "}" { $$ = ast::item(ast::Trait{take($2), ast::Path{take($4)}, take($6)}).release(); }

/* КОНСТАНТЫ */

ConstStmt : CONST ID ":" Type "=" Expr ";" { $$ = ast::item(ast::Const{take($2), own($4), own($6)}).release(); }
          | CONST ID ":" Type ";" { $$ = ast::item(ast::Const{take($2), own($4), {}}).release(); }

/* МОДУЛИ */

ModuleStmt : MOD ID "{" ItemListEmpty "}" { $$ = ast::item(ast::Module{take($2), take($4)}).release(); }

/* ОБЪЯВЛЕНИЯ ПЕРЕМЕННЫХ */

LetStmt : LET ID           "=" Expr ";" { $$ = new ast::Stmt{ast::LetStmt{take($2), false, {}, own($4)}}; }
        | LET ID ":" Type  "=" Expr ";" { $$ = new ast::Stmt{ast::LetStmt{take($2), false, own($4), own($6)}}; }
        | LET MUT ID           "=" Expr ";" { $$ = new ast::Stmt{ast::LetStmt{take($3), true, {}, own($5)}}; }
        | LET MUT ID ":" Type  "=" Expr ";" { $$ = new ast::Stmt{ast::LetStmt{take($3), true, own($5), own($7)}}; }
        | LET MUT ID ";" { $$ = new ast::Stmt{ast::LetStmt{take($3), true, {}, {}}}; }
        | LET MUT ID ":" Type  ";" { $$ = new ast::Stmt{ast::LetStmt{take($3), true, own($5), {}}}; }

/* ВЫРАЖЕНИЯ В ПОЗИЦИИ ОПЕРАТОРА */

ExprStmt : ExprWithoutBlock ";" { $$ = new ast::Stmt{ast::ExprStmt{own($1), true}}; }
         | ExprWithBlock { $$ = new ast::Stmt{ast::ExprStmt{own($1), false}}; }

/* СПИСКИ ВЫРАЖЕНИЙ */

ExprListEmpty : /* пусто */ { $$ = new ast::ExprList{}; }
              | ExprList "," { $$ = $1; }
              | ExprList { $$ = $1; }

ExprList : Expr { $$ = one<ast::ExprList>(own($1)); }
         | ExprList "," Expr { $$ = append($1, own($3)); }

/* [замечание 2] Expr = ExprNoStruct | StructExpr — единый нетерминал для большинства мест */
Expr : ExprNoStruct { $$ = $1; }
     | StructExpr { $$ = $1; }

/* ЛИТЕРАЛЫ */

Literal : INTEGER_LITERAL { $$ = ast::expr(ast::LiteralExpr{take($1)}).release(); }
        | FLOAT_LITERAL { $$ = ast::expr(ast::LiteralExpr{take($1)}).release(); }
        | BOOLEAN_LITERAL { $$ = ast::expr(ast::LiteralExpr{take($1)}).release(); }
        | STRING_LITERAL { $$ = ast::expr(ast::LiteralExpr{take($1)}).release(); }
        | RAW_STRING_LITERAL { $$ = ast::expr(ast::LiteralExpr{take($1)}).release(); }
        | CHAR_LITERAL { $$ = ast::expr(ast::LiteralExpr{take($1)}).release(); }
        ;

/* ВЫРАЖЕНИЯ */

/* [замечание 2] ExprWithoutBlock теперь краткий: ExprNoStruct или StructExpr */
ExprWithoutBlock : ExprNoStruct { $$ = $1; }
                 | StructExpr { $$ = $1; }

/* [замечание 2] ExprNoStruct — основной большой нетерминал без struct-литерала */
ExprNoStruct
    : Literal { $$ = $1; }

    /* арифметика */
    | ExprNoStruct "+" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Add, own($1), own($3)}).release(); }
    | ExprNoStruct "+" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Add, own($1), own($3)}).release(); }
    | ExprNoStruct "-" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Subtract, own($1), own($3)}).release(); }
    | ExprNoStruct "-" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Subtract, own($1), own($3)}).release(); }
    | ExprNoStruct "/" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Divide, own($1), own($3)}).release(); }
    | ExprNoStruct "/" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Divide, own($1), own($3)}).release(); }
    | ExprNoStruct "*" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Multiply, own($1), own($3)}).release(); }
    | ExprNoStruct "*" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Multiply, own($1), own($3)}).release(); }
    | ExprNoStruct "%" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Remainder, own($1), own($3)}).release(); }
    | ExprNoStruct "%" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Remainder, own($1), own($3)}).release(); }

    /* логика */
    | ExprNoStruct "&&" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::LogicalAnd, own($1), own($3)}).release(); }
    | ExprNoStruct "&&" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::LogicalAnd, own($1), own($3)}).release(); }
    | ExprNoStruct "||" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::LogicalOr, own($1), own($3)}).release(); }
    | ExprNoStruct "||" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::LogicalOr, own($1), own($3)}).release(); }

    /* присваивание */
    | ExprNoStruct "=" ExprNoStruct { $$ = ast::expr(ast::AssignExpr{own($1), own($3)}).release(); }
    | ExprNoStruct "=" ExprWithBlock { $$ = ast::expr(ast::AssignExpr{own($1), own($3)}).release(); }

    /* сравнения */
    | ExprNoStruct "==" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Equal, own($1), own($3)}).release(); }
    | ExprNoStruct "==" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Equal, own($1), own($3)}).release(); }
    | ExprNoStruct "!=" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::NotEqual, own($1), own($3)}).release(); }
    | ExprNoStruct "!=" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::NotEqual, own($1), own($3)}).release(); }
    | ExprNoStruct ">" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Greater, own($1), own($3)}).release(); }
    | ExprNoStruct ">" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Greater, own($1), own($3)}).release(); }
    | ExprNoStruct "<" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Less, own($1), own($3)}).release(); }
    | ExprNoStruct "<" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::Less, own($1), own($3)}).release(); }
    | ExprNoStruct ">=" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::GreaterEqual, own($1), own($3)}).release(); }
    | ExprNoStruct ">=" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::GreaterEqual, own($1), own($3)}).release(); }
    | ExprNoStruct "<=" ExprNoStruct { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::LessEqual, own($1), own($3)}).release(); }
    | ExprNoStruct "<=" ExprWithBlock { $$ = ast::expr(ast::BinaryExpr{ast::BinaryOp::LessEqual, own($1), own($3)}).release(); }

    /* унарные */
    | "-" ExprNoStruct %prec UMINUS { $$ = ast::expr(ast::UnaryExpr{ast::UnaryOp::Negate, own($2)}).release(); }
    | "-" ExprWithBlock    %prec UMINUS { $$ = ast::expr(ast::UnaryExpr{ast::UnaryOp::Negate, own($2)}).release(); }
    | "!" ExprNoStruct { $$ = ast::expr(ast::UnaryExpr{ast::UnaryOp::Not, own($2)}).release(); }
    | "!" ExprWithBlock { $$ = ast::expr(ast::UnaryExpr{ast::UnaryOp::Not, own($2)}).release(); }
    | "*" ExprNoStruct %prec USTAR { $$ = ast::expr(ast::UnaryExpr{ast::UnaryOp::Dereference, own($2)}).release(); }
    | "*" ExprWithBlock    %prec USTAR { $$ = ast::expr(ast::UnaryExpr{ast::UnaryOp::Dereference, own($2)}).release(); }
    | "&" ExprNoStruct { $$ = ast::expr(ast::BorrowExpr{own($2), false}).release(); }
    | "&" ExprWithBlock { $$ = ast::expr(ast::BorrowExpr{own($2), false}).release(); }
    | "&" MUT ExprNoStruct { $$ = ast::expr(ast::BorrowExpr{own($3), true}).release(); }
    | "&" MUT ExprWithBlock { $$ = ast::expr(ast::BorrowExpr{own($3), true}).release(); }
    | ExprNoStruct "?" { $$ = ast::expr(ast::TryExpr{own($1)}).release(); }

    /* массивы */
    | "[" ExprListEmpty "]" { $$ = ast::expr(ast::ArrayExpr{take($2)}).release(); }
    | "[" ExprNoStruct ";" ExprNoStruct "]" { $$ = ast::expr(ast::RepeatArrayExpr{own($2), own($4)}).release(); }
    | "[" ExprNoStruct ";" ExprWithBlock "]" { $$ = ast::expr(ast::RepeatArrayExpr{own($2), own($4)}).release(); }
    | "[" ExprWithBlock ";" ExprNoStruct "]" { $$ = ast::expr(ast::RepeatArrayExpr{own($2), own($4)}).release(); }
    | "[" ExprWithBlock ";" ExprWithBlock "]" { $$ = ast::expr(ast::RepeatArrayExpr{own($2), own($4)}).release(); }

    /* индексация */
    | ExprNoStruct "[" ExprNoStruct "]" { $$ = ast::expr(ast::IndexExpr{own($1), own($3)}).release(); }
    | ExprNoStruct "[" ExprWithBlock "]" { $$ = ast::expr(ast::IndexExpr{own($1), own($3)}).release(); }

    /* управление */
    | CONTINUE { $$ = ast::expr(ast::ContinueExpr{}).release(); }
    | BREAK { $$ = ast::expr(ast::BreakExpr{{}}).release(); }
    | BREAK ExprNoStruct { $$ = ast::expr(ast::BreakExpr{own($2)}).release(); }
    | BREAK ExprWithBlock { $$ = ast::expr(ast::BreakExpr{own($2)}).release(); }
    | RETURN { $$ = ast::expr(ast::ReturnExpr{{}}).release(); }
    | RETURN ExprNoStruct { $$ = ast::expr(ast::ReturnExpr{own($2)}).release(); }
    | RETURN ExprWithBlock { $$ = ast::expr(ast::ReturnExpr{own($2)}).release(); }

    /* диапазоны */
    | ".." { $$ = ast::expr(ast::RangeExpr{{}, {}}).release(); }
    | ".." ExprNoStruct { $$ = ast::expr(ast::RangeExpr{{}, own($2)}).release(); }
    | ".." ExprWithBlock { $$ = ast::expr(ast::RangeExpr{{}, own($2)}).release(); }
    | ExprNoStruct ".." { $$ = ast::expr(ast::RangeExpr{own($1), {}}).release(); }
    | ExprNoStruct ".." ExprNoStruct { $$ = ast::expr(ast::RangeExpr{own($1), own($3)}).release(); }
    | ExprNoStruct ".." ExprWithBlock { $$ = ast::expr(ast::RangeExpr{own($1), own($3)}).release(); }

    /* доступ к полям / методам / кортежам */
    | ExprNoStruct "." INTEGER_LITERAL { $$ = ast::expr(ast::TupleFieldExpr{own($1), take($3).spelling}).release(); }
    | ExprNoStruct "." ID { $$ = ast::expr(ast::FieldExpr{own($1), take($3)}).release(); }
    | ExprNoStruct "." ID "(" ExprListEmpty ")" { $$ = ast::expr(ast::MethodCallExpr{own($1), take($3), take($5)}).release(); }

    /* пути и вызовы */
    | Path { $$ = ast::expr(ast::PathExpr{take($1)}).release(); }
    | Path "(" ExprListEmpty ")" {
          auto callee = ast::expr(ast::PathExpr{take($1)});
          $$ = ast::expr(ast::CallExpr{std::move(callee), take($3)}).release();
      }

    /* скобки и приведение типа (внутри скобок — полный Expr) */
    | "(" Expr ")" { $$ = ast::expr(ast::ParenthesizedExpr{own($2)}).release(); }
    | "(" ExprWithBlock ")" { $$ = ast::expr(ast::ParenthesizedExpr{own($2)}).release(); }
    | ExprNoStruct AS Type { $$ = ast::expr(ast::CastExpr{own($1), own($3)}).release(); }
    ;

StructExpr : Path "{" StructExprFieldListEmpty "}" { $$ = ast::expr(ast::StructExpr{take($1), take($3)}).release(); }
           ;

PathPrefix : SUPER { $$ = new ast::Path{{"super"}}; }
           | CRATE { $$ = new ast::Path{{"crate"}}; }
           | SELF_VALUE { $$ = new ast::Path{{"self"}}; }
           | PathPrefix "::" SUPER { $$ = append($1, {"super"}); }
           ;

TypePath : ID { $$ = one<ast::Path>(take($1)); }
         | SELF_TYPE { $$ = new ast::Path{{"Self"}}; }
         | PathPrefix "::" ID { $$ = append($1, take($3)); }
         | TypePath "::" ID { $$ = append($1, take($3)); }
         ;

Path : TypePath { $$ = $1; }
     | SELF_VALUE { $$ = new ast::Path{{"self"}}; }
     ;

StructExprFieldListEmpty : /* пусто */ { $$ = new ast::StructFieldValues{}; }
                         | StructExprFieldList { $$ = $1; }
                         | StructExprFieldList "," { $$ = $1; }

StructExprFieldList : StructExprField { $$ = one<ast::StructFieldValues>(take($1)); }
                    | StructExprFieldList "," StructExprField { $$ = append($1, take($3)); }

StructExprField : ID ":" ExprNoStruct { $$ = new ast::StructFieldValue{take($1), own($3)}; }
                | ID ":" ExprWithBlock { $$ = new ast::StructFieldValue{take($1), own($3)}; }
                | ID ":" StructExpr { $$ = new ast::StructFieldValue{take($1), own($3)}; }

ExprWithBlock : BlockExpr { $$ = ast::expr(ast::BlockExpr{own($1)}).release(); }
              | LoopExpr { $$ = $1; }
              | IfExpr { $$ = $1; }

BlockExpr : "{" StmtList "}" { $$ = block(take($2)).release(); }
          | "{" ExprNoStruct "}" { $$ = block({}, own($2)).release(); }
          | "{" StructExpr "}" { $$ = block({}, own($2)).release(); }
          | "{" StmtList ExprNoStruct "}" { $$ = block(take($2), own($3)).release(); }
          | "{" StmtList StructExpr "}" { $$ = block(take($2), own($3)).release(); }
          | "{" "}" { $$ = block().release(); }

LoopExpr : InfiniteLoopExpr { $$ = $1; }
         | PredicateLoopExpr { $$ = $1; }
         | IteratorLoopExpr { $$ = $1; }

InfiniteLoopExpr : LOOP BlockExpr { $$ = ast::expr(ast::LoopExpr{own($2)}).release(); }

PredicateLoopExpr : WHILE ExprWithBlock BlockExpr { $$ = ast::expr(ast::WhileExpr{own($2), own($3)}).release(); }
                  | WHILE ExprNoStruct  BlockExpr { $$ = ast::expr(ast::WhileExpr{own($2), own($3)}).release(); }

IteratorLoopExpr : FOR ID IN ExprWithBlock BlockExpr { $$ = ast::expr(ast::ForExpr{take($2), own($4), own($5)}).release(); }
                 | FOR ID IN ExprNoStruct  BlockExpr { $$ = ast::expr(ast::ForExpr{take($2), own($4), own($5)}).release(); }

/* [замечание 3] Правая рекурсия: каждый else принадлежит ближайшему if */
IfExpr : IF ExprNoStruct  BlockExpr { $$ = ast::expr(ast::IfExpr{own($2), own($3), {}}).release(); }
       | IF ExprWithBlock BlockExpr { $$ = ast::expr(ast::IfExpr{own($2), own($3), {}}).release(); }
       | IF ExprNoStruct  BlockExpr ELSE BlockExpr { $$ = ast::expr(ast::IfExpr{own($2), own($3), ast::expr(ast::BlockExpr{own($5)})}).release(); }
       | IF ExprNoStruct  BlockExpr ELSE IfExpr { $$ = ast::expr(ast::IfExpr{own($2), own($3), own($5)}).release(); }
       | IF ExprWithBlock BlockExpr ELSE BlockExpr { $$ = ast::expr(ast::IfExpr{own($2), own($3), ast::expr(ast::BlockExpr{own($5)})}).release(); }
       | IF ExprWithBlock BlockExpr ELSE IfExpr { $$ = ast::expr(ast::IfExpr{own($2), own($3), own($5)}).release(); }

/* ТИПЫ */

Type : TypePath { $$ = ast::type(ast::PathType{take($1)}).release(); }
     | "[" Type ";" ExprNoStruct "]" { $$ = ast::type(ast::ArrayType{own($2), own($4)}).release(); }
     | "[" Type ";" ExprWithBlock "]" { $$ = ast::type(ast::ArrayType{own($2), own($4)}).release(); }

/* ВИДИМОСТЬ */

Visibility : PUB { $$ = ast::Visibility::Public; }
           | PUB "(" SUPER ")" { $$ = ast::Visibility::Parent; }
           | PUB "(" SELF_VALUE ")" { $$ = ast::Visibility::Current; }

%%