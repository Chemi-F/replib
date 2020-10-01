Programming with binders using Unbound
======================================

*Names* are the bane of every language implementation: they play an
unavoidable, central role, yet are tedious to deal with and surprisingly
tricky to get right. 

Unbound is a flexible and powerful library for programming with
names and binders, which makes programming with binders easy and
painless.  Built on top of RepLib's generic programming framework, it
does a lot of work behind the scenes to provide you with a seamless,
"it just works" experience.

This literate Haskell tutorial will walk you through the basics of
using Unbound.  The [Haddock documentation for
Unbound](http://hackage.haskell.org/package/unbound) is also a good
source of information.  For something more academic, you may also be
interested in reading

* [Stephanie Weirich, Brent Yorgey, and Tim Sheard. Binders
Unbound.](http://www.cis.upenn.edu/~byorgey/papers/binders-unbound.pdf)
Submitted, March 2011.

The untyped lambda calculus
---------------------------

Let's start by writing a simple untyped lambda calculus
interpreter. This will illustrate the basic functionality of Unbound.

**Preliminaries**

First, we need to enable lots of wonderful GHC extensions:

> {-# LANGUAGE MultiParamTypeClasses
>            , TemplateHaskell
>            , ScopedTypeVariables
>            , FlexibleInstances
>            , FlexibleContexts
>            , UndecidableInstances
>   #-}

You may be worried by `UndecidableInstances`.  Sadly, this is
necessary in order to typecheck the code generated by RepLib. Rest
assured, however, that the instances generated by RepLib *are*
decidable; it's just that GHC can't prove it. 

Now to import the library:

> import Unbound.LocallyNameless

We import the locally nameless implementation of Unbound (A nominal
implementation is also provided in `Unbound.Nominal`.  However, at the
moment it is likely full of bugs and is poorly documented, so we
recommend sticking with the locally nameless implementation for now.)

A few other imports we'll need for this particular example:

> import Control.Applicative
> import Control.Arrow ((+++))
> import Control.Monad
> import Control.Monad.Trans.Maybe
> import Control.Monad.Trans.Except
>
> import Text.Parsec hiding ((<|>), Empty)
> import qualified Text.Parsec.Token as P
> import Text.Parsec.Language (haskellDef)
>
> import qualified Text.PrettyPrint as PP
> import Text.PrettyPrint (Doc, (<+>))

**Representing terms**

We now declare a `Term` data type to represent lambda calculus terms.

> data Term = Var (Name Term)
>           | App Term Term
>           | Lam (Bind (Name Term) Term)
>   deriving Show

The `App` constructor is straightforward, but the other two
constructors are worth looking at in detail.

First, the `Var` constructor holds a `Name Term`.  `Name` is an
abstract type for representing names, provided by Unbound.  `Name`s
are indexed by the sorts of things to which they can refer (or more
precisely, the sorts of things which can be substituted for them).
Here, a variable is simply a name for some `Term`, so we use the type
`Name Term`.

Lambdas are where names are *bound*, so we use the special `Bind`
combinator, also provided by the library.  Something of type `Bind p b`
represents a pair consisting of a *pattern* `p` and a *body* `b`.  The
pattern may bind names which occur in `b`.  Here is where the power of
generic programming comes into play: we may use (almost) any types at
all as patterns and bodies, and Unbound will be able to handle it with
very little extra guidance from us.

In this particular case, a lambda simply binds a single name, so the
pattern is just a `Name Term`, and the body is just another `Term`.

Now we tell RepLib to automatically derive a bunch of
behind-the-scenes, boilerplate instances for `Term`:

> $(derive [''Term])

There are just a couple more things we need to do.  First, we make
`Term` an instance of `Alpha`, which provides most of the methods we
will need for working with the variables and binders within `Term`s.

> instance Alpha Term

What, no method definitions?  Nope!  In this case (and in most cases)
the default implementations, written in terms of those generic
instances we had RepLib derive for us, work just fine.  But in special
situations it's possible to override specific methods in the `Alpha`
class with our own implementations (see the documentation for an
example).

We only need to provide one more thing: a `Subst Term Term`
instance. In general, an instance for `Subst b a` means that we can
use the `subst` function to substitute things of type `b` for `Name`s
occurring in things of type `a`.  The only method we must implement
ourselves is `isvar`, which has the type

    isvar :: a -> Maybe (SubstName a b)

The documentation for `isvar` states "If the argument is a variable,
return its name wrapped with the 'SubstName' constructor. Return
`Nothing` for non-variable arguments."  Even the most sophisticated
generic programming library can't read our minds: we have to tell it
which values of our data type are variables (*i.e.* things that can be
substituted for).  For `Term` this is not hard:

> instance Subst Term Term where
>   isvar (Var v) = Just (SubstName v)
>   isvar _       = Nothing

That's all!

**Trying things out**

Now that we've got the necessary preliminaries set up, what can we do
with this?  First, let's define some convenient helper functions:

> lam :: String -> Term -> Term
> lam x t = Lam $ bind (string2Name x) t
>
> var :: String -> Term
> var = Var . string2Name

Notice that `string2Name` allows us to create a `Name` from a
`String`, and `bind` allows us to construct bindings.

We can test things out at the `ghci` prompt like so:

    *Main> lam "x" (lam "y" (var "x"))
    Lam (<x> Lam (<y> Var 1@0))

Don't worry about the `1@0` thing: Unbound handles all the details of
this for you.  However, if you must know, it is a *de Bruijn index*,
which refers to the 0th variable of the 1st (counting outwards from 0)
enclosing binding site; that is, to `x`.  Recall that the left-hand
side of a `Bind` can be an arbitrary data structure potentially
containing multiple names (a *pattern*), like a pair or a list; hence
the need for the index after the `@`.  Of course, in this particular
example we only ever bind one name at once, so the index after the `@`
will always be zero.

We can check that substitution works as we expect. Substituting for
`x` in a term where `x` does not occur free has no effect:

    *Main> subst (string2Name "x") (var "z") (lam "x" (var "x"))
    Lam (<x> Var 0@0)
    
If `x` does occur free, the substitution takes place as expected:

    *Main> subst (string2Name "x") (var "z") (lam "y" (var "x"))
    Lam (<y> Var z)

Finally, substitution is capture-avoiding:

    *Main> subst (string2Name "x") (var "y") (lam "y" (var "x"))
    Lam (<y> Var y)

It may look at first glance like `y` has been incorrectly captured, but
the fact that it has a *name* means it is free: if it had been
captured we would see `Lam (<y> Var 0@0)`.

**Evaluation**

The first thing we want to do is write an evaluator for our lambda
calculus.  Of course there are many ways to do this; for the sake of
simplicity and illustration, we will write an evaluator based on a
small-step, call-by-value operational semantics.

> -- A convenient synonym for mzero
> done :: MonadPlus m => m a
> done = mzero
>
> step :: Term -> MaybeT FreshM Term
> step (Var _) = done
> step (Lam _) = done
> step (App (Lam b) t2) = do
>   (x,t1) <- unbind b
>   return $ subst x t2 t1
> step (App t1 t2) =
>       App <$> step t1 <*> pure t2
>   <|> App <$> pure t1 <*> step t2

> lamFst :: Term -> (Name Term)
> lamFst (Lam b) = bindFst b
> lamSnd :: Term -> Term
> lamSnd (Lam b) = bindSnd b

> lam1 :: (Name Term) -> Term -> Term
> lam1 x t = Lam $ bind x t
> substRename :: [String] -> Term -> Term
> substRename xs (Var x)
>                   | elem (show x) xs == True = var ("Free " ++ show x)
>                   | otherwise                = (Var x)
> substRename xs (App t1 t2) = (App (substRename xs t1) (substRename xs t2))
> substRename xs (Lam b)     = let x = lamFst (Lam b)
>                                  t = lamSnd (Lam b)
>                                  in (lam1 x (substRename ((show x):xs) t))

We define a `step` function with the type `Term -> MaybeT FreshM
Term`.  `FreshM` is a monad provided by the binding library to handle
fresh name generation.  It's fairly simple but works just fine in many
situations.  (If you need to, you can create your own custom monad,
make it an instance of the `Fresh` class, and use it in place of
`FreshM`.)  In order to signal whether a reduction step has taken
place, we add failure capability with the `MaybeT` monad transformer.
We may freely intermix `FreshM` (which also comes in a transformer
variant, `FreshMT`) with all the standard monad transformers found in
the `transformers` package.

`step` tries to reduce the given term one step if possible.  Variables
and lambdas cannot be reduced at all, so in those cases we signal that
we are done. If the input term is an application of a lambda to
another term, we must do a beta-reduction.  We first use `unbind` to
destruct the binding inside the `Lam` constructor; it automatically
chooses a fresh name for the bound variable and gives us back a pair
of the variable and body.  We then call `subst` to perform the
appropriate substitution.

Otherwise, we must have an application of something other than a
lambda.  In this case we try reducing first the left-hand and then the
right-hand term.

Finally, we define an `eval` function as the transitive closure of
`step`, and run it with `runFreshM`:

> tc :: (Monad m, Functor m) => (a -> MaybeT m a) -> (a -> m a)
> tc f a = do
>   ma' <- runMaybeT (f a)
>   case ma' of
>     Just a' -> tc f a'
>     Nothing -> return a
>
> eval :: Term -> Term
> eval x = runFreshM (tc step x)

**Parsing**

We can use [Parsec](http://hackage.haskell.org/package/parsec) to
write a tiny parser for our lambda calculus:

> lexer    = P.makeTokenParser haskellDef
> parens   = P.parens lexer
> brackets = P.brackets lexer
> ident    = P.identifier lexer
> 
> parseTerm = parseAtom `chainl1` (pure App)
> 
> parseAtom = parens parseTerm
>         <|> var <$> ident
>         <|> lam <$> (brackets ident) <*> parseTerm
> 
> runTerm :: String -> Either ParseError Term
> runTerm = (id +++ eval) . parse parseTerm ""

In fact, there's nothing particularly special about this parser with
respect to the binding library: we just get to reuse our `var` and
`lam` functions from before, with the result that strings like `"([x]
[y] x) x"` are parsed into terms with all the scoping properly
resolved.

To check that it works, let's compute 2 + 3:

    *Main> runTerm "([m][n][s][z] m s (n s z)) ([s] [z] s (s z)) ([s][z] s (s (s z))) s z"
    Right (App (Var s) (App (Var s) (App (Var s) (App (Var s) (App (Var s) (Var z))))))

2 + 3 is still 5, and all is right with the world.

**Pretty-printing and LFresh**

Now we want to write a pretty-printer for our lambda calculus (to use
in our fantastic type checking error messages, once we get around to
adding an amazing, sophisticated type system).  Here's a first attempt:

> class Pretty' p where
>   ppr' :: (Applicative m, Fresh m) => p -> m Doc
>
> instance Pretty' Term where
>   ppr' (Var x)     = return . PP.text . show $ x
>   ppr' (App t1 t2) = PP.parens <$> ((<+>) <$> ppr' t1 <*> ppr' t2)
>   ppr' (Lam b)     = do
>     (x, t) <- unbind b
>     ((PP.brackets . PP.text . show $ x) <+>) <$> ppr' t

However, there's a problem:

    *Main> runFreshM $ ppr' (lam "x" (lam "y" (lam "z" (var "y"))))
    [x] [y1] [z2] y1

Ugh, what are those numbers doing there?  The problem is that `unbind`
always generates a new globally fresh name no matter what other names
are or aren't in scope.  This is fine for evaluation, but for
pretty-printing terms that include bound names it's rather ugly.  For
nicer printing we'll need something a bit more sophisticated.

That something is the `LFresh` type class, which gives a slightly
different interface for generating *locally fresh* names (as opposed
to `Fresh` which generates globally fresh names).  A standard
`LFreshM` monad is provided (along with a corresponding transformer,
`LFreshMT`) which is an instance of `LFresh`.

    class Monad m => LFresh m where
      -- | Pick a new name that is fresh for the current (implicit) scope.
      lfresh  :: Rep a => Name a -> m (Name a)
      -- | Avoid the given names when freshening in the subcomputation.
      avoid   :: [AnyName] -> m a -> m a

Monads which are instances of `LFresh` maintain a set of "currently
in-scope" names which are to be avoided when generating new
names. `lfresh` generates a name which is guaranteed not to be in the
set, and `avoid` runs a subcomputation with some additional names
added to the in-scope set.  You probably won't need to call these
methods explicitly very often; more useful are some methods built on
top of these such as `lunbind`:

    lunbind :: (LFresh m, Alpha p, Alpha t) => Bind p t -> ((p, t) -> m r) -> m r

`lunbind` corresponds to `unbind` but works in an `LFresh` context.
It destructs a binding, avoiding only names curently in scope, and
runs a subcomputation while additionally avoiding the chosen name(s).

Let's rewrite our pretty-printer in terms of `LFresh`.  The only
change we need to make is to use continuation-passing style for the
call to `lunbind` in place of the normal monadic sequencing used with
`unbind`.

> class Pretty p where
>   ppr :: (Applicative m, LFresh m) => p -> m Doc
>
> instance Pretty Term where
>   ppr (Var x)     = return . PP.text . show $ x
>   ppr (App t1 t2) = PP.parens <$> ((<+>) <$> ppr t1 <*> ppr t2)
>   ppr (Lam b)     =
>     lunbind b $ \(x,t) ->
>       ((PP.brackets . PP.text . show $ x) <+>) <$> ppr t

 freshTest :: [String] -> Term -> Term
 freshTest xs (Var x)     = (Var x)
 freshTest xs (App t1 t2) = (App (freshTest xs t1) (freshTest xs t2))

 freshLam :: Term -> Bind (Name Term) Term
 freshLam (Lam t) = t

 freshLamBind :: Bind a b -> Term
 freshLamBind (bind x (Var x)) = var "x"

 class Pretty p where
   pprTest :: (Applicative m, LFresh m) => [String] -> p -> m Doc
 
 instance Pretty Term where
   pprTest xs (Var x)     = if (elem (show x) xs) then return . PP.text $ "zzz"
                            else return . PP.text . show $ x
   pprTest xs (App t1 t2) = PP.parens <$> ((<+>) <$> pprTest xs t1 <*> pprTest xs t2)
   pprTest xs (Lam b)     =
     lunbind b $ \(x,t) ->
       ((PP.brackets . PP.text . show $ x) <+>) <$> pprTest ((show x):xs) t

Let's try it:

    *Main> runLFreshM $ ppr (lam "x" (lam "y" (lam "z" (var "y"))))
    [x] [y] [z] y
  
    *Main> runLFreshM $ ppr (lam "x" (lam "y" (lam "y" (var "y"))))
    [x] [y] [y1] y1
  
Much better!

Note: the tutorial from this point on is still under construction, so
expect some rough edges -- although you may still find the material
useful!

A simple dependent calculus
---------------------------

To illustrate some of the more advanced features of RepLib's binding
library, let's consider a simple dependent calculus, defined as
follows:

[XXX put ott output here or something?  How to present the calculus?]

This is about a simple as we can get while retaining dependency of
types on terms, but it is already rather interesting with regards to
binding structure.  The main point of interest is the way that
*telescopes* work: in a term such as

[XXX \[A:*, B:A -> *, x:A, t:A -> B x]. t x]

every variable bound in the telescope is in scope not only in the body
of the abstraction but also in the type annotations of later bindings
in the telescope.  For example, `x` shows up both in the type of `t`
and in the body of the abstraction.

We can imagine a way to encode this using only `Bind`, but it would be
rather ugly. [XXX explain why it would be ugly: subtrees etc., doesn't
correspond to way we have imagined the syntax, etc.]

Instead, we can define a type `Exp` of expressions like this:

> data Exp = EVar (Name Exp)
>          | EStar
>          | ELam (Bind Tele Exp)
>          | EApp Exp [Exp]
>          | EPi (Bind Tele Exp)
>   deriving Show

There's nothing remarkable about this yet; the definition of `Exp`
corresponds exactly to the grammar we gave for expressions earlier,
and refers to a data type `Tele` of telescopes.  However, we can
already see that the definition of `Tele` will have to be somewhat
interesting: `ELam` and `EPi` declare telescopes as patterns which
bind variables within the body (an `Exp`), but as we noted before,
telescopes also have their own internal binding structure.

> data Tele = Empty
>           | Cons (Rebind (Name Exp, Embed Exp) Tele)
>   deriving Show

A telescope can be empty, of course, or else it is a variable binding
like `(x:A)` followed by another telescope, in which the variable is
bound.  However, it won't do to use `Bind`: the variable is bound *not
only* in the following telescope, but *also* in the body of the
abstraction which forms the outer context.  So instead of `Bind` we
use `Rebind`. `Rebind p b` specifies that the pattern `p` is bound in
the body `b`, but is *also* made available to be bound in another
outer context.  (Of course, that outer context might itself be a
`Rebind`, in which case the same variable would be bound in yet
another outer context, and so on.)

We are not quite done: `Rebind (Name Exp, Exp) Tele` would not be
correct, since this would specify that any variables occurring in the
`Exp` are bound in the telescope (and also in the outer context), but
this is not correct.  The `Exp` is a type annotation for the name, and
any names occurring in it are actually *references* to previously
bound names, not binding sites themselves.  For this purpose the
`Embed` wrapper is provided, which specifies that the wrapped type --
which would otherwise be considered a binding pattern -- is only an
annotation whose names refer back to previous bindings.

Pop quiz: why would

    | Cons (Rebind (Name Exp) (Embed Exp, Tele))

also be incorrect?

(Answer: because then variables would be bound within their own type
annotations.)

Now for some instances: we derive generic representations for `Exp`
and `Tele`, and make them both instances of `Alpha`. We also define a
`Subst` instance so we can substitute expressions for variables in
other expressions.

> $(derive [''Exp, ''Tele])
>
> instance Alpha Exp
> instance Alpha Tele

> instance Subst Exp Exp where
>   isvar (EVar v) = Just (SubstName v)
>   isvar _        = Nothing

We also need to be able to substitute expressions for variables
occurring in telescopes.  However, since telescopes do not contain
free expression variables directly (only binding sites, which are
never the target of a substitution), the default definition of `isvar
= const Nothing` is all we need, and the generic programming framework
takes care of the rest.

> instance Subst Exp Tele

We define some convenient smart constructors as before:

> evar :: String -> Exp
> evar = EVar . string2Name
> 
> elam :: [(String, Exp)] -> Exp -> Exp
> elam t b = ELam (bind (mkTele t) b)
> 
> epi :: [(String, Exp)] -> Exp -> Exp
> epi t b = EPi (bind (mkTele t) b)
>
> earr :: Exp -> Exp -> Exp
> earr t1 t2 = epi [("_", t1)] t2
> 
> eapp :: Exp -> Exp -> Exp
> eapp a b = EApp a [b]
> 
> mkTele :: [(String, Exp)] -> Tele
> mkTele []          = Empty
> mkTele ((x,e) : t) = Cons (rebind (string2Name x, Embed e) (mkTele t))

These are fairly straightforward, and we note only the second case of
`mkTele`, where we use `rebind` for creating a `Rebind` structure, and
wrap `e` in an `Embed` constructor.

We can test things out so far by creating a few example terms.  Here
is the polymorphic identity function:

    *Main> elam [("A", EStar), ("x", evar "A")] (evar "x")
    ELam (<(Cons (<<(A,{EStar})>> Cons (<<(x,{EVar 0@0})>> Empty)))> EVar 0@1)

Inside the `ELam` we have the whole telescope inside angle brackets
(indicating the entire thing is a binding pattern), followed by the
body of the lambda, `EVar 0@1`, indicating it is a reference to the
first enclosing binding pattern (that is, the telescope), and
specifically to the second variable bound within the pattern (that is,
`x`).  Within the telescope, there is a binding for `A` with an
annotation (in curly braces) of `EStar`, followed by a binding for
`x`, with an annotation of `EVar 0@0` -- that is, `A`.

    *Main> :{
    *Main| elam [ ("A", EStar)
    *Main|      , ("B", earr (evar "A") EStar)
    *Main|      , ("x", evar "A")
    *Main|      , ("t", earr (evar "A") (eapp (evar "B") (evar "x")))
    *Main|      ]
    *Main|   (eapp (evar "t") (evar "x"))
    *Main| :}
    
    ELam (<(Cons (<<(A,{EStar})>> 
            Cons (<<(B,{EPi (<(Cons (<<(_,{EVar 0@0})>> Empty))> 
                          EStar)})>> 
            Cons (<<(x,{EVar 1@0})>> 
            Cons (<<(t,{EPi (<(Cons (<<(_,{EVar 2@0})>> Empty))> 
                          EApp (EVar 2@0) [EVar 1@0])})>> 
            Empty)))))> 
      EApp (EVar 0@3) [EVar 0@2])

We will also need functions for appending two telescopes, and for
looking up a name in a telescope.  Both these functions illustrate the
use of `unrebind`, which opens a `Rebind` structure similarly to the
way that `unbind` opens `Bind`s.  However, it is different in one
important respect: while the output of `unbind` must be in a monad for
fresh name generation, the output of `unrebind` is pure.  This is
because `Rebind`s can only ever occur within an enclosing `Bind`, so
by the time we get around to opening a `Rebind`, fresh names have
already been chosen for the binders by a call to `unbind`, and they
need not be freshened again.

We also define a monad `M` which will serve as the context for our
type checker.

> appTele :: Tele -> Tele -> Tele
> appTele Empty     t2 = t2
> appTele (Cons rb) t2 = Cons (rebind p (appTele t1' t2))
>   where (p, t1') = unrebind rb
> 
> type M = ExceptT String LFreshM
>
> lookUp :: Name Exp -> Tele -> M Exp
> lookUp n Empty     = throwE $ "Not in scope: " ++ show n
> lookUp v (Cons rb) | v == x    = return a
>                    | otherwise = lookUp v t'
>   where ((x, Embed a), t') = unrebind rb

(We also note in passing that `appTele` and `lookUp` would be perfect
opportunities to use GHC's `ViewPatterns`, but for simplicity's sake
we leave this fun to the reader.)

We can now write a type checker for our toy language.  From the point
of view of the binding library, there's nothing too remarkable about
it: we use `lunbind` to take apart binders when inferring the types of
lambdas, applications, and pis, and use substitution both when
checking the types of argument lists (`checkList`) and when
substituting the arguments to an application into the type of the
result (`multiSubst`).

> unPi :: Exp -> M (Bind Tele Exp)
> unPi (EPi bnd) = return bnd
> unPi e         = throwE $ "Expected pi type, got " ++ show e ++ " instead"
> 
> infer :: Tele -> Exp -> M Exp
> infer g (EVar x)  = lookUp x g
> infer _ EStar     = return EStar
> infer g (ELam bnd) = do
>   lunbind bnd $ \(delta, m) -> do
>     b <- infer (g `appTele` delta) m
>     return . EPi $ bind delta b
> infer g (EApp m ns) = do
>   bnd <- unPi =<< infer g m
>   lunbind bnd $ \(delta, b) -> do
>     checkList g ns delta
>     multiSubst delta ns b
> infer g (EPi bnd) = do
>   lunbind bnd $ \(delta, b) -> do
>     check (g `appTele` delta) b EStar
>     return EStar
> 
> check :: Tele -> Exp -> Exp -> M ()
> check g m a = do
>   b <- infer g m
>   checkEq b a
> 
> checkList :: Tele -> [Exp] -> Tele -> M ()
> checkList _ [] Empty = return ()
> checkList g (e:es) (Cons rb) = do
>   let ((x, Embed a), t') = unrebind rb
>   check g e a
>   checkList (subst x e g) (subst x e es) (subst x e t')
> checkList _ _ _ = throwE $ "Unequal number of parameters and arguments"
> 
> multiSubst :: Tele -> [Exp] -> Exp -> M Exp
> multiSubst Empty     [] e = return e
> multiSubst (Cons rb) (e1:es) e = multiSubst t' es e'
>   where ((x,_), t') = unrebind rb
>         e' = subst x e1 e
> multiSubst _ _ _ = throwE $ "Unequal lengths in multiSubst" -- shouldn't happen
> 
> -- A conservative, inexpressive notion of equality, just for the sake
> -- of the example.
> checkEq :: Exp -> Exp -> M ()
> checkEq e1 e2 = if aeq e1 e2 
>                   then return () 
>                   else throwE $ "Couldn't match: " ++ show e1 ++ " " ++ show e2

XXX insert type *checking* example (checking pi-type of a lambda) as
illustration of unbind2
