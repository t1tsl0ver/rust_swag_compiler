/* ТОКЕНЫ */

/* --- Ключевые слова --- */
%token AS BREAK CONST CONTINUE CRATE ELSE ENUM FALSE FN FOR IF IMPL IN
%token LET LOOP MOD MUT PUB RETURN SELF_VALUE STRUCT SUPER TRAIT TRUE WHILE

/* --- Идентификаторы и литералы --- */
%token ID
%token INTEGER_LITERAL_DEC INTEGER_LITERAL_BIN INTEGER_LITERAL_OCT INTEGER_LITERAL_HEX
%token FLOAT_LITERAL STRING_LITERAL RAW_STRING_LITERAL CHAR_LITERAL

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

Item : SimpleItem
     | Visibility SimpleItem

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
            | FN ID "(" FuncParamListEmpty ")" "->" Type ";"
            | FN ID "(" FuncParamListEmpty ")" "->" IMPL Type ";"

ImplFuncStmt : FN ID "(" FuncParamListEmpty ")" BlockExpr
             | FN ID "(" FuncParamListEmpty ")" "->" Type BlockExpr
             | FN ID "(" FuncParamListEmpty ")" "->" IMPL Type BlockExpr

FuncParamListEmpty : /* empty */
                   | FuncParamList

FuncParamList : SELF_VALUE
              | "&" SELF_VALUE
              | "&" MUT SELF_VALUE
              | FuncParam
              | FuncParamList "," FuncParam

FuncParam : ID ":" Type
          | ID ":" IMPL Type
          | MUT ID ":" Type
          | MUT ID ":" IMPL Type
          | ID ":" "&" MUT Type
          | ID ":" "&" MUT IMPL Type
          | ID ":" "&" Type
          | ID ":" "&" IMPL Type

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

StructField : ID ":" Type
            | Visibility ID ":" Type

TupleStruct : STRUCT ID "(" TupleFieldListEmpty ")"

TupleFieldListEmpty : /* empty */
                    | TupleFieldList
                    | TupleFieldList ","

TupleFieldList : Type
               | Visibility Type
               | TupleFieldList "," Type
               | TupleFieldList "," Visibility Type

/* ENUM */

EnumStmt : ENUM ID "{" EnumItemListEmpty "}"

EnumItemListEmpty : /* empty */
                  | ","
                  | EnumItemList
                  | EnumItemList ","

EnumItemList : EnumItem
             | EnumItemList "," EnumItem

EnumItem : ID
         | Visibility ID
         | ID "=" ExprWithBlock
         | ID "=" ExprWithoutBlock
         | Visibility ID "=" ExprWithBlock
         | Visibility ID "=" ExprWithoutBlock
         | Visibility ID "{" StructFieldListEmpty "}"
         | ID "{" StructFieldListEmpty "}"

/* IMPL */

ImplStmt : IMPL Type "{" AssociatedItemListEmpty "}"
         | IMPL PathCallExpr FOR Type "{" AssociatedItemListEmpty "}"

AssociatedItemListEmpty : /* empty */
                        | AssociatedItemList

AssociatedItemList : AssociatedItem
                   | AssociatedItemList AssociatedItem

AssociatedItem : FuncStmt
              | ConstStmt
              | Visibility FuncStmt
              | Visibility ConstStmt

/* TRAIT */

TraitStmt : TRAIT ID "{" AssociatedItemListEmpty "}"
          | TRAIT ID ":" ID "{" AssociatedItemListEmpty "}"

/* CONST */

ConstStmt : CONST ID ":" Type "=" ExprWithBlock ";"
          | CONST ID ":" Type "=" ExprWithoutBlock ";"
          | CONST ID ":" Type ";"

/* MODULE */

ModuleStmt : MOD ID "{" ItemListEmpty "}"

/* LET */

LetStmt : LET ID "=" ExprWithBlock ";"
        | LET ID "=" ExprWithoutBlock ";"
        | LET ID ":" Type "=" ExprWithBlock ";"
        | LET ID ":" Type "=" ExprWithoutBlock ";"
        | LET MUT ID ";"
        | LET MUT ID ":" Type ";"
        | LET MUT ID "=" ExprWithBlock ";"
        | LET MUT ID "=" ExprWithoutBlock ";"
        | LET MUT ID ":" Type "=" ExprWithBlock ";"
        | LET MUT ID ":" Type "=" ExprWithoutBlock ";"

/* EXPR STMT */

ExprStmt : ExprWithoutBlock ";"
         | ExprWithBlock

/* EXPR LIST */

ExprListEmpty : /* empty */
              | ExprList ","
              | ExprList

ExprList : ExprWithBlock
         | ExprWithoutBlock
         | ExprList "," ExprWithBlock
         | ExprList "," ExprWithoutBlock

/* INT LITERAL */

IntLiteral : INTEGER_LITERAL_DEC
           | INTEGER_LITERAL_BIN
           | INTEGER_LITERAL_OCT
           | INTEGER_LITERAL_HEX

/* EXPRESSIONS */

ExprWithoutBlock
    : CHAR_LITERAL
    | STRING_LITERAL
    | RAW_STRING_LITERAL
    | IntLiteral
    | FLOAT_LITERAL
    | TRUE
    | FALSE

    /* арифметика */
    | ExprWithoutBlock "+" ExprWithoutBlock
    | ExprWithoutBlock "+" ExprWithBlock
    | ExprWithoutBlock "-" ExprWithoutBlock
    | ExprWithoutBlock "-" ExprWithBlock
    | ExprWithoutBlock "/" ExprWithoutBlock
    | ExprWithoutBlock "/" ExprWithBlock
    | ExprWithoutBlock "*" ExprWithoutBlock
    | ExprWithoutBlock "*" ExprWithBlock
    | ExprWithoutBlock "%" ExprWithoutBlock
    | ExprWithoutBlock "%" ExprWithBlock

    /* логика */
    | ExprWithoutBlock "&&" ExprWithoutBlock
    | ExprWithoutBlock "&&" ExprWithBlock
    | ExprWithoutBlock "||" ExprWithoutBlock
    | ExprWithoutBlock "||" ExprWithBlock

    /* присваивание */
    | ExprWithoutBlock "=" ExprWithoutBlock
    | ExprWithoutBlock "=" ExprWithBlock

    /* сравнения */
    | ExprWithoutBlock "==" ExprWithoutBlock
    | ExprWithoutBlock "==" ExprWithBlock
    | ExprWithoutBlock "!=" ExprWithoutBlock
    | ExprWithoutBlock "!=" ExprWithBlock
    | ExprWithoutBlock ">" ExprWithoutBlock
    | ExprWithoutBlock ">" ExprWithBlock
    | ExprWithoutBlock "<" ExprWithoutBlock
    | ExprWithoutBlock "<" ExprWithBlock
    | ExprWithoutBlock ">=" ExprWithoutBlock
    | ExprWithoutBlock ">=" ExprWithBlock
    | ExprWithoutBlock "<=" ExprWithoutBlock
    | ExprWithoutBlock "<=" ExprWithBlock

    /* унарные */
    | "-" ExprWithoutBlock %prec UMINUS
    | "-" ExprWithBlock    %prec UMINUS
    | "!" ExprWithoutBlock
    | "!" ExprWithBlock
    | "*" ExprWithoutBlock %prec USTAR
    | "*" ExprWithBlock    %prec USTAR
    | "&" ExprWithoutBlock
    | "&" ExprWithBlock
    | "&" MUT ExprWithoutBlock
    | "&" MUT ExprWithBlock
    | ExprWithoutBlock "?"

    /* массивы */
    | "[" ExprListEmpty "]"
    | "[" ExprWithoutBlock ";" ExprWithoutBlock "]"
    | "[" ExprWithoutBlock ";" ExprWithBlock    "]"
    | "[" ExprWithBlock    ";" ExprWithoutBlock "]"
    | "[" ExprWithBlock    ";" ExprWithBlock    "]"

    /* индексация */
    | ExprWithoutBlock "[" ExprWithoutBlock "]"
    | ExprWithoutBlock "[" ExprWithBlock    "]"

    /* управление */
    | CONTINUE
    | BREAK
    | BREAK ExprWithoutBlock
    | BREAK ExprWithBlock
    | RETURN
    | RETURN ExprWithoutBlock
    | RETURN ExprWithBlock

    /* диапазоны */
    | ".."
    | ".." ExprWithoutBlock
    | ".." ExprWithBlock
    | ExprWithoutBlock ".."
    | ExprWithoutBlock ".." ExprWithoutBlock
    | ExprWithoutBlock ".." ExprWithBlock

    /* доступ к полям / методам / кортежам */
    | ExprWithoutBlock "." IntLiteral
    | ExprWithoutBlock "." ID
    | ExprWithoutBlock "." ID "(" ExprListEmpty ")"

    /* пути и вызовы */
    | PathCallExpr
    | PathCallExpr "(" ExprListEmpty ")"

    /* создание структуры */
    | ExprWithoutBlock "{" StructExprFieldList "}"

    /* скобки и приведение типа */
    | "(" ExprWithBlock    ")"
    | "(" ExprWithoutBlock ")"
    | ExprWithoutBlock AS Type

PathCallExpr : ID
             | SUPER
             | SELF_VALUE
             | CRATE
             | PathCallExpr "::" ID

StructExprFieldList : StructExprField
                    | "," StructExprField
                    | StructExprFieldList "," StructExprField

StructExprField : ID ":" ExprWithoutBlock
                | ID ":" ExprWithBlock

ExprWithBlock : BlockExpr
              | LoopExpr
              | IfExpr

BlockExpr : "{" StmtList "}"
          | "{" ExprWithoutBlock "}"
          | "{" StmtList ExprWithoutBlock "}"
          | "{" "}"

LoopExpr : InfiniteLoopExpr
         | PredicateLoopExpr
         | IteratorLoopExpr

InfiniteLoopExpr : LOOP BlockExpr

PredicateLoopExpr : WHILE ExprWithBlock    BlockExpr
                  | WHILE ExprWithoutBlock BlockExpr

IteratorLoopExpr : FOR ID IN ExprWithBlock    BlockExpr
                 | FOR ID IN ExprWithoutBlock BlockExpr

IfExpr : SimpleIfElseExpr
       | SimpleIfElseExpr ELSE BlockExpr

SimpleIfElseExpr : SimpleIfExpr
                 | SimpleIfElseExpr ELSE SimpleIfExpr

SimpleIfExpr : IF ExprWithoutBlock BlockExpr
             | IF ExprWithBlock    BlockExpr

/* TYPE */

Type : PathCallExpr
     | "[" Type ";" ExprWithBlock    "]"
     | "[" Type ";" ExprWithoutBlock "]"

/* VISIBILITY */

Visibility : PUB
           | PUB "(" SUPER ")"
           | PUB "(" SELF_VALUE ")"

%%