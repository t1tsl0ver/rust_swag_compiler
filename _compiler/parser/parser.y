/* ТОКЕНЫ */

/* --- Ключевые слова --- */
%token AS BREAK CONST CONTINUE CRATE ELSE ENUM FN FOR IF IMPL IN
%token LET LOOP MOD MUT PUB RETURN SELF_TYPE SELF_VALUE STRUCT SUPER TRAIT WHILE

/* --- Идентификаторы и литералы --- */
%token ID
%token INTEGER_LITERAL FLOAT_LITERAL BOOLEAN_LITERAL
%token STRING_LITERAL RAW_STRING_LITERAL CHAR_LITERAL

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

/* PROGRAM */

Program : ItemListEmpty

/* STATEMENT */

StmtList : Stmt
         | StmtList Stmt

Stmt : ";"
     | LetStmt
     | ExprStmt
     | ConstStmt

ItemListEmpty : /* empty */
              | ItemList

ItemList : Item
         | ItemList Item

/* [замечание 1] Visibility_opt объединяет пустой и Visibility варианты */
Visibility_opt : /* empty */
               | Visibility

Item : Visibility_opt SimpleItem

SimpleItem : FuncStmt
           | StructStmt
           | EnumStmt
           | ImplStmt
           | TraitStmt
           | ConstStmt
           | ModuleStmt

/* FUNCTION */

FuncStmt : DecFuncStmt
         | ImplFuncStmt

DecFuncStmt : FN ID "(" FuncParamListEmpty ")" ";"
            | FN ID "(" FuncParamListEmpty ")" "->" ReturnType ";"

ImplFuncStmt : FN ID "(" FuncParamListEmpty ")" BlockExpr
             | FN ID "(" FuncParamListEmpty ")" "->" ReturnType BlockExpr

/* [замечание 1] ReturnType объединяет Type и IMPL Type */
ReturnType : Type
           | IMPL Type

FuncParamListEmpty : /* empty */
                   | FuncParamList

/* [замечание 1] self-параметры вынесены в SelfParam */
FuncParamList : SelfParam
              | FuncParam
              | FuncParamList "," FuncParam

SelfParam : SELF_VALUE
          | "&" SELF_VALUE
          | "&" MUT SELF_VALUE

/* [замечание 1] FuncParam: выделены нетерминалы для модификаторов типа */
FuncParam : MutOpt ID ":" ParamType

MutOpt : /* empty */
       | MUT

/* [замечание 1] ParamType объединяет все варианты типов параметра */
ParamType : ImplOpt Type
          | "&" ImplOpt Type
          | "&" MUT ImplOpt Type

ImplOpt : /* empty */
        | IMPL

/* STRUCT */

StructStmt : StructStruct
           | TupleStruct

StructStruct : STRUCT ID "{" StructFieldListEmpty "}"
             | STRUCT ID ";"

StructFieldListEmpty : /* empty */
                     | StructFieldList
                     | StructFieldList ","

StructFieldList : StructField
                | StructFieldList "," StructField

StructField : Visibility_opt ID ":" Type

TupleStruct : STRUCT ID "(" TupleFieldListEmpty ")"

TupleFieldListEmpty : /* empty */
                    | TupleFieldList
                    | TupleFieldList ","

TupleFieldList : TupleField
               | TupleFieldList "," TupleField

TupleField : Visibility_opt Type

/* ENUM */

EnumStmt : ENUM ID "{" EnumItemListEmpty "}"

EnumItemListEmpty : /* empty */
                  | EnumItemList
                  | EnumItemList ","

EnumItemList : EnumItem
             | EnumItemList "," EnumItem

EnumItem : Visibility_opt ID
         | Visibility_opt ID "=" Expr
         | Visibility_opt ID "{" StructFieldListEmpty "}"

/* IMPL */

ImplStmt : IMPL Type "{" AssociatedItemListEmpty "}"
         | IMPL TypePath FOR Type "{" AssociatedItemListEmpty "}"

AssociatedItemListEmpty : /* empty */
                        | AssociatedItemList

AssociatedItemList : AssociatedItem
                   | AssociatedItemList AssociatedItem

AssociatedItem : Visibility_opt FuncStmt
               | Visibility_opt ConstStmt

/* TRAIT */

TraitStmt : TRAIT ID "{" AssociatedItemListEmpty "}"
          | TRAIT ID ":" ID "{" AssociatedItemListEmpty "}"

/* CONST */

ConstStmt : CONST ID ":" Type "=" Expr ";"
          | CONST ID ":" Type ";"

/* MODULE */

ModuleStmt : MOD ID "{" ItemListEmpty "}"

/* LET */

LetStmt : LET ID           "=" Expr ";"
        | LET ID ":" Type  "=" Expr ";"
        | LET MUT ID           "=" Expr ";"
        | LET MUT ID ":" Type  "=" Expr ";"
        | LET MUT ID ";"
        | LET MUT ID ":" Type  ";"

/* EXPR STMT */

ExprStmt : ExprWithoutBlock ";"
         | ExprWithBlock

/* EXPR LIST */

ExprListEmpty : /* empty */
              | ExprList ","
              | ExprList

ExprList : Expr
         | ExprList "," Expr

/* [замечание 2] Expr = ExprNoStruct | StructExpr — единый нетерминал для большинства мест */
Expr : ExprNoStruct
     | StructExpr

/* LITERALS */

Literal : INTEGER_LITERAL
        | FLOAT_LITERAL
        | BOOLEAN_LITERAL
        | STRING_LITERAL
        | RAW_STRING_LITERAL
        | CHAR_LITERAL
        ;

/* EXPRESSIONS */

/* [замечание 2] ExprWithoutBlock теперь краткий: ExprNoStruct или StructExpr */
ExprWithoutBlock : ExprNoStruct
                 | StructExpr

/* [замечание 2] ExprNoStruct — основной большой нетерминал без struct-литерала */
ExprNoStruct
    : Literal

    /* арифметика */
    | ExprNoStruct "+" ExprNoStruct
    | ExprNoStruct "+" ExprWithBlock
    | ExprNoStruct "-" ExprNoStruct
    | ExprNoStruct "-" ExprWithBlock
    | ExprNoStruct "/" ExprNoStruct
    | ExprNoStruct "/" ExprWithBlock
    | ExprNoStruct "*" ExprNoStruct
    | ExprNoStruct "*" ExprWithBlock
    | ExprNoStruct "%" ExprNoStruct
    | ExprNoStruct "%" ExprWithBlock

    /* логика */
    | ExprNoStruct "&&" ExprNoStruct
    | ExprNoStruct "&&" ExprWithBlock
    | ExprNoStruct "||" ExprNoStruct
    | ExprNoStruct "||" ExprWithBlock

    /* присваивание */
    | ExprNoStruct "=" ExprNoStruct
    | ExprNoStruct "=" ExprWithBlock

    /* сравнения */
    | ExprNoStruct "==" ExprNoStruct
    | ExprNoStruct "==" ExprWithBlock
    | ExprNoStruct "!=" ExprNoStruct
    | ExprNoStruct "!=" ExprWithBlock
    | ExprNoStruct ">" ExprNoStruct
    | ExprNoStruct ">" ExprWithBlock
    | ExprNoStruct "<" ExprNoStruct
    | ExprNoStruct "<" ExprWithBlock
    | ExprNoStruct ">=" ExprNoStruct
    | ExprNoStruct ">=" ExprWithBlock
    | ExprNoStruct "<=" ExprNoStruct
    | ExprNoStruct "<=" ExprWithBlock

    /* унарные */
    | "-" ExprNoStruct %prec UMINUS
    | "-" ExprWithBlock    %prec UMINUS
    | "!" ExprNoStruct
    | "!" ExprWithBlock
    | "*" ExprNoStruct %prec USTAR
    | "*" ExprWithBlock    %prec USTAR
    | "&" ExprNoStruct
    | "&" ExprWithBlock
    | "&" MUT ExprNoStruct
    | "&" MUT ExprWithBlock
    | ExprNoStruct "?"

    /* массивы */
    | "[" ExprListEmpty "]"
    | "[" ExprNoStruct ";" ExprNoStruct "]"
    | "[" ExprNoStruct ";" ExprWithBlock "]"
    | "[" ExprWithBlock ";" ExprNoStruct "]"
    | "[" ExprWithBlock ";" ExprWithBlock "]"

    /* индексация */
    | ExprNoStruct "[" ExprNoStruct "]"
    | ExprNoStruct "[" ExprWithBlock "]"

    /* управление */
    | CONTINUE
    | BREAK
    | BREAK ExprNoStruct
    | BREAK ExprWithBlock
    | RETURN
    | RETURN ExprNoStruct
    | RETURN ExprWithBlock

    /* диапазоны */
    | ".."
    | ".." ExprNoStruct
    | ".." ExprWithBlock
    | ExprNoStruct ".."
    | ExprNoStruct ".." ExprNoStruct
    | ExprNoStruct ".." ExprWithBlock

    /* доступ к полям / методам / кортежам */
    | ExprNoStruct "." INTEGER_LITERAL
    | ExprNoStruct "." ID
    | ExprNoStruct "." ID "(" ExprListEmpty ")"

    /* пути и вызовы */
    | Path
    | Path "(" ExprListEmpty ")"

    /* скобки и приведение типа (внутри скобок — полный Expr) */
    | "(" Expr ")"
    | "(" ExprWithBlock ")"
    | ExprNoStruct AS Type
    ;

StructExpr : Path "{" StructExprFieldListEmpty "}"
           ;

PathPrefix : SUPER
           | CRATE
           | SELF_VALUE
           | PathPrefix "::" SUPER
           ;

TypePath : ID
         | SELF_TYPE
         | PathPrefix "::" ID
         | TypePath "::" ID
         ;

Path : TypePath
     | SELF_VALUE
     ;

StructExprFieldListEmpty : /* empty */
                         | StructExprFieldList
                         | StructExprFieldList ","

StructExprFieldList : StructExprField
                    | StructExprFieldList "," StructExprField

StructExprField : ID ":" ExprNoStruct
                | ID ":" ExprWithBlock
                | ID ":" StructExpr

ExprWithBlock : BlockExpr
              | LoopExpr
              | IfExpr

BlockExpr : "{" StmtList "}"
          | "{" ExprNoStruct "}"
          | "{" StructExpr "}"
          | "{" StmtList ExprNoStruct "}"
          | "{" StmtList StructExpr "}"
          | "{" "}"

LoopExpr : InfiniteLoopExpr
         | PredicateLoopExpr
         | IteratorLoopExpr

InfiniteLoopExpr : LOOP BlockExpr

PredicateLoopExpr : WHILE ExprWithBlock BlockExpr
                  | WHILE ExprNoStruct  BlockExpr

IteratorLoopExpr : FOR ID IN ExprWithBlock BlockExpr
                 | FOR ID IN ExprNoStruct  BlockExpr

/* [замечание 3] Правая рекурсия: каждый else принадлежит ближайшему if */
IfExpr : IF ExprNoStruct  BlockExpr
       | IF ExprWithBlock BlockExpr
       | IF ExprNoStruct  BlockExpr ELSE BlockExpr
       | IF ExprNoStruct  BlockExpr ELSE IfExpr
       | IF ExprWithBlock BlockExpr ELSE BlockExpr
       | IF ExprWithBlock BlockExpr ELSE IfExpr

/* TYPE */

Type : TypePath
     | "[" Type ";" ExprNoStruct "]"
     | "[" Type ";" ExprWithBlock "]"

/* VISIBILITY */

Visibility : PUB
           | PUB "(" SUPER ")"
           | PUB "(" SELF_VALUE ")"

%%
