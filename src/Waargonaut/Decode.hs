{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoImplicitPrelude     #-}
{-# LANGUAGE OverloadedStrings     #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
-- |
--
-- Types and Functions for turning JSON into Haskell.
--
-- We will work through a basic example, using the following type:
--
-- @
-- data Person = Person
--   { _personName                    :: Text
--   , _personAge                     :: Int
--   , _personAddress                 :: Text
--   , _personFavouriteLotteryNumbers :: [Int]
--   }
--   deriving (Eq, Show)
-- @
--
-- Expect the following JSON as input:
--
-- @
-- { \"name\":    \"Krag\"
-- , \"age\":     88
-- , \"address\": \"Red House 4, Three Neck Lane, Greentown.\"
-- , \"numbers\": [86,3,32,42,73]
-- }
-- @
--
-- We'll need to import the 'Waargonaut.Decode' module. You may of course use whatever import scheme you like,
-- I prefer this method:
--
-- @
-- import Waargonaut.Decode (Decoder)
-- import qualified Waargonaut.Decode as D
-- @
--
-- The 'Waargonaut.Decode.Decoder' is based upon a data structure called a @zipper@. This allows us
-- to move around the JSON structure using arbitrary movements. Such as
-- 'Waargonaut.Decode.moveRight1' to move from a key on an object to the value at that key. Or
-- 'Waargonaut.Decode.down' to move into the first element of an array or object. Waargonaut
-- provides a suite of these functions to move around and dissect the JSON input.
--
-- This zipper is combined with a 'Control.Monad.State.StateT' transformer that maintains a history of your movements.
-- So if the JSON input is not as your 'Waargonaut.Decode.Decoder' expects you are given a complete
-- path to where things went awry.
--
-- Decoding a JSON value is done by moving the cursor to specific points of interest, then focusing
-- on that point with a 'Waargonaut.Decode.Decoder' of the desired value.
--
-- NB: The "Monad" constraint is provided as a flexibility for more interesting and nefarious uses
-- of 'Waargonaut.Decode.Decoder'.
--
-- Here is the 'Waargonaut.Decode.Decoder' for our @Person@ data type. It will help to turn on the
-- @OverloadedStrings@ language pragma as these functions expect 'Data.Text.Text' input.
--
-- @
-- personDecoder :: Monad f => Decoder f Person
-- personDecoder = D.withCursor $ \\c -> do
--   o     <- D.down c
--   name  <- D.fromKey "name" D.text o
--   age   <- D.fromKey "age" D.int o
--   addr  <- D.fromKey "address" D.text o
--   lotto <- D.fromKey "numbers" (D.list D.int) o
--   pure $ Person name age addr lotto
-- @
--
-- The 'Waargonaut.Decode.withCursor' function provides our cursor: @c@. We then move
-- 'Waargonaut.Decode.down' into the JSON object. The reasons for this are:
--
-- * The initial cursor position is always at the very beginning of the input. On freshly indexed
--   JSON input, using our example, the cursor will be at:
--
-- @
-- \<cursor\>{ \"name\": \"Krag\"
--         , \"age\": 88
--         ...
-- @
--
-- * Because of the above reason, our decoder makes an assumption about the placement of the cursor
--   on the JSON input. This sort of assumption is reasonable for reasons we will go over later.
--
-- The cursor output from 'Waargonaut.Decode.down' will located here:
--
-- @
-- { \<cursor\>\"name\": \"Krag\"
--   , \"age\": 88
--   ...
-- @
--
-- Then we use one of the helper functions, 'Waargonaut.Decode.fromKey' to find the "key - value"
-- pair that we're interested in and decode it for us:
--
-- @
-- fromKey :: Monad f => Text -> Decoder f b -> JCurs -> DecodeResult f b
-- @
--
-- We could also write this 'Waargonaut.Decode.Decoder' as:
--
-- @
-- personDecoder2 :: Monad f => Decoder f Person
-- personDecoder2 = Person
--   \<$> D.atKey \"name\" D.text
--   \<*> D.atKey \"age\" D.int
--   \<*> D.atKey \"address\" D.text
--   \<*> D.atKey \"numbers\" (D.list D.int)
-- @
--
-- Using the 'Waargonaut.Decode.atKey' function which tries to handle those basic movements for us
-- and has those assumptions included. Very useful for when the JSON input closely mirrors your data
-- structure.
--
-- @
-- atKey :: Monad f => Text -> Decoder f a -> Decoder f a
-- @
--
-- The next part is being able to apply our 'Waargonaut.Decode.Decoder' to some input. Assuming we
-- have some input. We want to pass it through our @personDecoder@ for a result. Waargonaut uses
-- the <https://hackage.haskell.org/package/parsers parsers> package to define its parser. This
-- allows you to choose your own favourite parsing library to do the heavy lifting. Provided it
-- implements the right typeclasses from the @parsers@ package.
--
-- To apply a 'Waargonaut.Decode.Decoder' to some input you will need one of the
-- decoder running functions from 'Waargonaut.Decode'. There are a few different
-- functions provided for some of the common input text-like types.:
--
-- @
-- decodeFromByteString
--   :: ( CharParsing f
--      , Monad f
--      , Monad g
--      , Show e
--      )
--   => (forall a. f a -> ByteString -> Either e a)
--   -> Decoder g x
--   -> ByteString
--   -> g (Either (DecodeError, CursorHistory) x)
-- @
--
--
-- As well as a parsing function from your parsing library of choice, that also
-- has an implementation of the 'Text.Parser.Char.CharParsing' typeclass from @parsers@. We will
-- use @attoparsec@ in the examples below.
--
-- @
-- import qualified Data.Attoparsec.ByteString as AB
-- @
--
-- @
-- decodeFromByteString AB.parseOnly personDecode inp
-- @
--
-- Which will run the @personDecode@ 'Waargonaut.Decode.Decoder' using the parsing function
-- (@AB.parseOnly@), starting at the cursor from the top of the @inp@ input.
--
-- Again the 'Control.Monad.Monad' constraint is there so that you have more options available for utilising the
-- 'Waargonaut.Decode.Decoder' in ways we haven't thought of.
--
-- Or if you don't need the 'Control.Monad.Monad' constraint then you may use 'Waargonaut.Decode.pureDecodeFromByteString'.
-- This function specialises the 'Control.Monad.Monad' constraint to 'Data.Functor.Identity'.:
--
-- @
-- pureDecodeFromByteString
--   :: ( Monad f
--      , CharParsing f
--      , Show e
--      )
--   => (forall a. f a -> ByteString -> Either e a)
--   -> Decoder Identity x
--   -> ByteString
--   -> Either (DecodeError, CursorHistory) x
-- @
--
-- @
-- pureDecodeFromByteString AB.parseOnly personDecode inp
-- @
--
-- Waargonaut provides some default implementations using the <https://hackage.haskell.org/package/attoparsec attoparsec> package in the @Waargonaut.Attoparsec@ module. These functions have exactly the same behaviour as the functions above, without the need to provide the parsing function.
module Waargonaut.Decode
  (
    -- * Types
    CursorHistory
  , Cursor
  , DecodeResult (..)
  , Decoder (..)
  , JCurs (..)
  , Err (..)
  , JsonType (..)

    -- * Runners
  , module Waargonaut.Decode.Runners

    -- * Helpers
  , generaliseDecoder
  , DI.ppCursorHistory

    -- * Cursors
  , withCursor
  , mkCursor
  , cursorRankL
  , manyMoves
  , down
  , up
  , DI.try
  , moveRightN
  , moveRight1
  , moveLeftN
  , moveLeft1
  , moveToKey
  , moveToRankN

    -- * Decoding at cursor
  , jsonAtCursor
  , fromKey
  , atKey
  , focus

    -- * Attempting decoding
  , fromKeyOptional
  , atKeyOptional

    -- * Inspection
  , withType
  , jsonTypeAt

    -- * Provided Decoders
  , leftwardCons
  , rightwardSnoc
  , foldCursor
  , rank
  , prismD
  , prismDOrFail
  , prismDOrFail'
  , json
  , int
  , scientific
  , integral
  , string
  , strictByteString
  , lazyByteString
  , unboundedChar
  , boundedChar
  , text
  , bool
  , null
  , nonemptyAt
  , nonempty
  , listAt
  , list
  , objectAsKeyValuesAt
  , objectAsKeyValues
  , withDefault
  , maybeOrNull
  , either
  , oneOf
  , passKeysToValues

  ) where

import           GHC.Word                                       (Word64)

import           Control.Lens                                   (Cons, Lens',
                                                                 Prism', Snoc,
                                                                 cons, lens,
                                                                 matching,
                                                                 modifying,
                                                                 preview, snoc,
                                                                 traverseOf,
                                                                 view, ( # ),
                                                                 (.~), (^.),
                                                                 _Wrapped)
import           Control.Monad.Error.Lens                       (throwing)

import           Prelude                                        (Bool, Bounded,
                                                                 Char, Eq, Int,
                                                                 Integral,
                                                                 String, (-),
                                                                 (==), fromIntegral)

import           Control.Applicative                            (Applicative (..))
import           Control.Category                               ((.))
import           Control.Monad                                  (Monad (..),
                                                                 (=<<), (>=>))
import           Control.Monad.Morph                            (embed,
                                                                 generalize)

import           Control.Monad.Except                           (catchError,
                                                                 lift,
                                                                 liftEither)
import           Control.Monad.Reader                           (ReaderT (..),
                                                                 ask,
                                                                 runReaderT)
import           Control.Monad.State                            (MonadState)

import           Control.Error.Util                             (note)
import           Control.Monad.Error.Hoist                      ((<!?>), (<?>))

import           Data.Either                                    (Either (..))
import qualified Data.Either                                    as Either (either)
import           Data.Foldable                                  (Foldable, elem,
                                                                 foldl, foldr)
import           Data.Function                                  (const, flip,
                                                                 ($), (&))
import           Data.Functor                                   (fmap, (<$),
                                                                 (<$>))
import           Data.Functor.Alt                               ((<!>))
import           Data.Functor.Identity                          (Identity)
import           Data.Monoid                                    (mempty)
import           Data.Scientific                                (Scientific)

import           Data.List.NonEmpty                             (NonEmpty ((:|)))
import           Data.Maybe                                     (Maybe (..),
                                                                 fromMaybe,
                                                                 maybe)
import           Natural                                        (Natural,
                                                                 replicate,
                                                                 successor',
                                                                 zero')

import           Data.Text                                      (Text)

import           Data.ByteString                                (ByteString)
import qualified Data.ByteString                                as BS
import qualified Data.ByteString.Lazy                           as BL

import           HaskellWorks.Data.Positioning                  (Count)
import qualified HaskellWorks.Data.Positioning                  as Pos

import qualified HaskellWorks.Data.BalancedParens.FindOpen      as BP

import           HaskellWorks.Data.Bits                         ((.?.))
import           HaskellWorks.Data.TreeCursor                   (TreeCursor (..))

import           HaskellWorks.Data.Json.Standard.Cursor.Fast (Cursor)
import qualified HaskellWorks.Data.Json.Standard.Cursor.Generic as JC

import           Waargonaut.Decode.Error                        (AsDecodeError (..),
                                                                 DecodeError (..),
                                                                 Err (..))
import           Waargonaut.Decode.ZipperMove                   (ZipperMove (..))
import           Waargonaut.Types                               (Json)

import qualified Waargonaut.Decode.Internal                     as DI

import           Waargonaut.Decode.Runners

import           Waargonaut.Decode.Types                        (CursorHistory, DecodeResult (..),
                                                                 Decoder (..),
                                                                 JCurs (..),
                                                                 JsonType (..),
                                                                 jsonTypeAt,
                                                                 mkCursor)

-- | Function to define a 'Waargonaut.Decode.Decoder' for a specific data type.
--
-- For example, given the following data type:
--
-- @
-- data Image = Image
--   { _imageW        :: Int
--   , _imageH        :: Int
--   , _imageTitle    :: Text
--   , _imageAnimated :: Bool
--   , _imageIDs      :: [Int]
--   }
-- @
--
-- We can use 'Waargonaut.Decode.withCursor' to write a decoder that
-- will be given a cursor that we can use to build the data types that
-- we need.
--
-- @
-- imageDecoder :: Monad f => Decoder f Image
-- imageDecoder = withCursor $ \\curs -> D.down curs >>= Image
--   \<$> D.fromKey \"Width\" D.int curs
--   \<*> D.fromKey \"Height\" D.int curs
--   \<*> D.fromKey \"Title\" D.text curs
--   \<*> D.fromKey \"Animated\" D.bool curs
--   \<*> D.fromKey \"IDs\" intArray curs
-- @
--
-- It's up to you to provide a cursor that is at the correct position for a
-- 'Waargonaut.Decode.Decoder' to operate, but building decoders in this way simplifies creating
-- decoders for larger structures, as the smaller pieces contain fewer
-- assumptions. This encourages greater reuse of decoders and simplifies the
-- debugging process.
--
withCursor
  :: (JCurs -> DecodeResult f a)
  -> Decoder f a
withCursor g = Decoder $ \p ->
  DI.runDecoder' $ DI.withCursor' (flip runReaderT p . unDecodeResult . g)

-- | Lens for accessing the 'rank' of the 'JsonCursor'. The 'rank' forms part of
-- the calculation that is the cursors current position in the index.
--
cursorRankL :: Lens' Cursor Count
cursorRankL = lens JC.cursorRank (\c r -> c { JC.cursorRank = r })

-- | Execute the given function @n@ times.
manyMoves :: Monad m => Natural -> (b -> m b) -> b -> m b
manyMoves i g = foldl (>=>) pure (replicate i g)

-- | Generalise a 'Decoder' that has been specialised to 'Identity' back to some 'Monad f'.
generaliseDecoder :: Monad f => Decoder Identity a -> Decoder f a
generaliseDecoder dr = Decoder (\p -> embed generalize . runDecoder dr p)
{-# INLINE generaliseDecoder #-}

-- | Execute the given cursor movement function, throwing a 'FailedToMove' error
-- if it is unsuccessful, recording the new position in history if it is
-- successful.
moveCursBasic
  :: Monad f
  => (Cursor -> Maybe Cursor)
  -> ZipperMove
  -> JCurs
  -> DecodeResult f JCurs
moveCursBasic f m c =
  traverseOf _Wrapped f c <?> FailedToMove m >>= recordRank m

-- | Move the cursor down or into the child of the current cursor position.
--
-- The following examples use "*" to represent the cursor position.
--
-- Starting position:
--
-- @ *{"fred": 33, "sally": 44 } @
--
-- After moving 'down':
--
-- @ { *"fred": 33, "sally": 44 } @
--
-- This function will also move into the elements in an array:
--
-- Starting position:
--
-- @ *[1,2,3] @
--
-- After moving 'down':
--
-- @ [*1,2,3] @
--
-- This function is essential when dealing with the inner elements of objects or
-- arrays. As you must first move 'down' into the focus. However, you cannot
-- move down into an empty list or empty object. The reason for this is that
-- there will be nothing in the index for the element at the first position.
-- Thus the movement will be considered invalid.
--
-- These will fail if you attempt to move 'down':
--
-- @ *[] @
--
-- @ *{} @
--
down
  :: Monad f
  => JCurs
  -> DecodeResult f JCurs
down =
  moveCursBasic firstChild D

-- | Move the cursor up into the parent of the current cursor position.
--
-- The following examples use "*" to represent the cursor position.
--
-- Starting position:
--
-- @ { "fred": 33, *"sally": 44 } @
--
-- After moving 'up':
--
-- @ *{"fred": 33, "sally": 44 } @
--
up
  :: Monad f
  => JCurs
  -> DecodeResult f JCurs
up =
  moveCursBasic parent U

-- | Given a 'rank' value, attempt to move the cursor directly to that position.
--
-- Returns a 'InputOutOfBounds' error if that position is invalid.
--
moveToRankN
  :: Monad f
  => Word64
  -> JCurs
  -> DecodeResult f JCurs
moveToRankN newRank c =
  if JC.balancedParens (c ^. _Wrapped) .?. Pos.lastPositionOf newRank
  then pure $ c & _Wrapped . cursorRankL .~ newRank
  else throwing _InputOutOfBounds newRank

-- | Move the cursor rightwards @n@ times.
--
-- Starting position:
--
-- @ [*1, 2, 3] @
--
-- After @moveRightN 2@:
--
-- @ [1, 2, *3] @
--
moveRightN
  :: Monad f
  => Natural
  -> JCurs
  -> DecodeResult f JCurs
moveRightN i =
  moveCursBasic (manyMoves i nextSibling) (R i)

-- | Helper function to move right once.
moveRight1
  :: Monad f
  => JCurs
  -> DecodeResult f JCurs
moveRight1 =
  moveRightN (successor' zero')

-- | Helper function to move left once.
--
-- Starting position:
--
-- @ [1, 2, *3] @
--
-- Ater 'moveLeft1':
--
-- @ [1, *2, 3] @
moveLeft1
  :: Monad f
  => JCurs
  -> DecodeResult f JCurs
moveLeft1 jc =
  let
    c         = jc ^. _Wrapped
    rnk       = c ^. cursorRankL
    setRank r = jc & _Wrapped . cursorRankL .~ r
    prev      = rnk - 1
  in
    setRank <$> BP.findOpen (JC.balancedParens c) prev <?> InputOutOfBounds prev

-- | Move the cursor leftwards @n@ times.
moveLeftN
  :: Monad f
  => Natural
  -> JCurs
  -> DecodeResult f JCurs
moveLeftN i =
  manyMoves i moveLeft1

-- | Using the given parsing function, attempt to decode the value of the
-- 'ByteString' at the current cursor position.
jsonAtCursor
  :: Monad f
  => (ByteString -> Either DecodeError a)
  -> JCurs
  -> DecodeResult f a
jsonAtCursor p jc = do
  let
    c   = jc ^. _Wrapped
    rnk = c ^. cursorRankL

    leading = Pos.toCount $ JC.jsonCursorPos c
    txt = BS.drop (fromIntegral leading) $ JC.cursorText c

  if JC.balancedParens c .?. Pos.lastPositionOf rnk
    then liftEither (p txt)
    else throwing _InputOutOfBounds rnk

-- Internal function to record the current rank of the cursor into the zipper history
recordRank
  :: MonadState CursorHistory f
  => ZipperMove
  -> JCurs
  -> f JCurs
recordRank mv c =
  c <$ modifying _Wrapped (`snoc` (mv, c ^. _Wrapped . cursorRankL))

-- | Using the given 'Decoder', try to decode the current focus.
--
-- @
-- myIntList <- focus (list int) cursor
-- @
--
focus
  :: Monad f
  => Decoder f a
  -> JCurs
  -> DecodeResult f a
focus decoder curs = DecodeResult $ do
  p <- ask
  lift $ runDecoder decoder p curs

-- | Attempt to move to the value at a given key on the current JSON object.
-- This will only work if you have already moved 'down' into the JSON object,
-- because the cursor allows you to step over an entire object in a single. It has
-- to be told to move into the object first, otherwise it will not look in the
-- correct location for keys.
--
-- Cursor position indicated by "*".
--
-- Assuming cursor positioned here:
--
-- @ *{ "foo": 33, "fieldB": "pew pew" } @
--
-- This won't work, because we're AT the object, not IN the object:
-- @
-- moveToKey "foo" cursor
-- @
--
-- This will work, because we've moved 'down' INTO the object:
-- @
-- down cursor >>= moveToKey "foo"
-- @
--
moveToKey
  :: Monad f
  => Text
  -> JCurs
  -> DecodeResult f JCurs
moveToKey k c = do
  -- Tease out the key
  k' <- DI.try (focus text c) <!?> (_KeyDecodeFailed # ())

  -- Are we at the key we want to be at ?
  if k' == k
    -- Then move into the THING at the key
    then recordRank (DAt k) c >> moveRight1 c
    -- Try jump to the next key index
    else ( DI.try (moveRightN (successor' (successor' zero')) c) <!?> (_KeyNotFound # k) ) >>= moveToKey k

-- | Move to the first occurence of this key, as per 'moveToKey' and then
-- attempt to run the given 'Decoder' on that value, returning the result.
--
-- This decoder does not assume you have moved into the object.
--
-- @
-- ...
-- txtVal <- fromKey "foo" text c
-- ...
-- @
--
fromKey
  :: ( Monad f
     )
  => Text
  -> Decoder f b
  -> JCurs
  -> DecodeResult f b
fromKey k d =
  moveToKey k >=> focus d

-- | A simplified version of 'fromKey' that takes a 'Text' value indicating a
-- key to be moved to and decoded using the given 'Decoder f a'. If you don't
-- need any special cursor movements to reach the list of keys you require, you
-- could use this function to build a trivial 'Decoder' for a record type:
--
-- This decoder assumes it is positioned at the top of an object and will move
-- 'down' each time, before attempting to find the given key.
--
-- @
-- data MyRec = MyRec { fieldA :: Text, fieldB :: Int }
--
-- myRecDecoder :: Decoder f MyRec
-- myRecDecoder = MyRec
--   \<$> atKey \"field_a\" text
--   \<*> atKey \"field_b\" int
-- @
--
atKey
  :: Monad f
  => Text
  -> Decoder f a
  -> Decoder f a
atKey k d =
  withCursor (down >=> fromKey k d)

-- | A version of 'fromKey' that returns its result in 'Maybe'. If the key is
-- not present in the object, 'Nothing' is returned. If the key is present,
-- decoding will be performed as with 'fromKey'.
fromKeyOptional
  :: Monad f
  => Text
  -> Decoder f b
  -> JCurs
  -> DecodeResult f (Maybe b)
fromKeyOptional k d c =
  focus' =<< catchError (pure <$> moveToKey k c) (\de -> case de of
    KeyNotFound _ -> pure Nothing
    _             -> throwing _DecodeError de)
  where
    focus' = maybe (pure Nothing) (fmap Just . focus d)

-- | A version of 'atKey' that returns its result in 'Maybe'. If the key is
-- not present in the object, 'Nothing' is returned. If the key is present,
-- decoding will be performed as with 'atKey'.
--
-- For example, if a key could be absent and could be null if present,
-- it could be decoded as follows:
--
-- @
-- join \<$> atKeyOptional \"key\" (maybeOrNull text)
-- @
atKeyOptional
  :: Monad f
  => Text
  -> Decoder f b
  -> Decoder f (Maybe b)
atKeyOptional k d = withCursor (down >=> fromKeyOptional k d)

-- | Used internally in the construction of the basic 'Decoder's. Takes a 'Text'
-- description of the thing you expect to find at the current cursor, and a
-- function to convert the 'Json' structure found there into something else.
--
-- Useful if you want to decide how a 'Json' value is converted to another type.
--
atCursor
  :: Monad f
  => Text
  -> (Json -> Maybe c)
  -> Decoder f c
atCursor m c = withCursor $ \curs -> do
  p <- ask
  jsonAtCursor p curs >>=
    liftEither . note (ConversionFailure m) . c

-- | Attempt to work with a 'JCurs' provided the type of 'Json' at the current
-- position matches your expectations.
--
-- Such as:
--
-- @
-- withType JsonTypeArray d
-- @
--
-- @d@ will only be entered if the cursor at the current position is a JSON
-- array: '[]'.
--
withType
  :: Monad f
  => JsonType
  -> (JCurs -> DecodeResult f a)
  -> JCurs
  -> DecodeResult f a
withType t d c =
  if elem t $ jsonTypeAt (unJCurs c) then d c
  else throwing _TypeMismatch t

-- | Higher order function for combining a folding function with repeated cursor
-- movements. This lets you combine arbitrary cursor movements with an accumulating
-- function.
--
-- The functions 'leftwardCons' and 'rightwardSnoc' are both implemented using
-- this function.
--
-- @
-- leftwardCons = foldCursor (flip cons) moveLeft1
-- @
--
-- @
-- rightwardSnoc = foldCursor snoc moveRight1
-- @
--
foldCursor
  :: Monad f
  => (b -> a -> b)
  -> (JCurs -> DecodeResult f JCurs)
  -> b
  -> Decoder f a
  -> JCurs
  -> DecodeResult f b
foldCursor nom f s elemD curs = DecodeResult . ReaderT $ \p ->
  DI.foldCursor' s nom
    (flip runReaderT p . unDecodeResult . f)
    (DI.Decoder' $ runDecoder elemD p)
    curs

-- | A specialised decoder for moving over a JSON object where the keys are
-- values that you would like to have as part of the value at the different
-- keys.
--
-- An example of such an input is:
--
-- @
-- { \"Collection\" : {
--   \"BobsInput_ce43dff22\": {
--     \"someValue\": \"Some data\"
--   },
--   \"FredsInput_a4b32def\": {
--     \"someValue\": \"Some different data\"
--   }
-- }
-- @
--
-- Where those key values like \"XInput_YYYY\" are to be included in the object.
--
-- Given a type like this:
--
-- @
-- data ContainsItsKey = ContainsItsKey
--   { _containsItsKey_KeyValue :: Text
--   , _containsItsKey_SomeValue :: Text
--   }
-- @
--
-- To decode the above you would use this function like so:
--
-- @
-- takesKeyDecoder :: Monad f => Text -> Decoder f ContainsItsKey
-- takesKeyDecoder k = ContainsItsKey k \<$\> D.atKey \"someValue\" D.text
--
-- collectionDecoder :: Monad f => Decoder f [ContainsItsKey]
-- collectionDecoder = D.atKey \"Collection\" $ D.passKeysToValues [] D.text takesKeyDecoder
-- @
--
passKeysToValues
  :: ( Snoc c c v v
     , Monad f
     )
  => c
  -> Decoder f k
  -> (k -> Decoder f v)
  -> Decoder f c
passKeysToValues empty dK kDV = withCursor $ down >=> foldCursor snoc
  (moveRightN (successor' (successor' zero'))) empty
  (withCursor $ \c' -> focus dK c' >>= \k -> moveRight1 c' >>= focus (kDV k))

-- | Helper function for "pattern matching" on a decoded value to some Haskell
-- value. The 'Text' argument is used in the error message should this decoder
-- fail. Normally it would simply be the name of the type you are writing the
-- decoder for.
--
-- This is useful for decoding sum types, such as:
--
-- @
-- data MyEnum
--   = A
--   | B
--   | C
--
-- decodeMyEnum :: Monad f => Decoder f MyEnum
-- decodeMyEnum = D.oneOf D.text \"MyEnum\"
--   [ (\"a\", A)
--   , (\"b\", B)
--   , (\"c\", C)
--   ]
--
-- decodeMyEnumFromInt :: Monad f => Decoder f MyEnum
-- decodeMyEnumFromInt = D.oneOf D.int \"MyEnum\"
--   [ (1, A)
--   , (2, B)
--   , (3, C)
--   ]
-- @
--
oneOf
  :: ( Foldable g
     , Monad f
     , Eq a
     )
  => Decoder f a
  -> Text
  -> g (a, b)
  -> Decoder f b
oneOf d l =
  foldr (\i x -> g i <!> x) err
  where
    g (a,b) = d >>= \t -> if t == a then pure b else err
    err = throwing _ConversionFailure l

-- | From the current cursor position, move leftwards one position at a time and
-- push each @a@ onto the front of some 'Cons' structure.
leftwardCons
  :: ( Monad f
     , Cons s s a a
     )
  => s
  -> Decoder f a
  -> JCurs
  -> DecodeResult f s
leftwardCons =
  foldCursor (flip cons) moveLeft1

-- | From the current cursor position, move rightwards one position at a time,
-- and append the @a@ to some 'Snoc' structure.
rightwardSnoc
  :: ( Monad f
     , Snoc s s a a
     )
  => s
  -> Decoder f a
  -> JCurs
  -> DecodeResult f s
rightwardSnoc =
  foldCursor snoc moveRight1

-- | Decoder for some 'Integral' type. This conversion is walked through Mayan,
-- I mean, 'Scientific' to try to avoid numeric explosion issues.
integral :: (Monad f, Integral n, Bounded n) => Decoder f n
integral = atCursor "integral" DI.integral'

-- | At the given cursor position, return the 'Count' or 'rank' of that
-- position. Useful if you want to build a map of a complicated structure such that
-- you're able to optimise your 'Decoder' by using 'moveToRankN' instead of
-- individual cursor movements.
rank :: Monad f => Decoder f Count
rank = withCursor (pure . view cursorRankL . unJCurs)

-- | Create a 'Decoder' from a 'Control.Lens.Prism''.
--
prismD
  :: Monad f
  => Prism' a b
  -> Decoder f a
  -> Decoder f (Maybe b)
prismD p =
  fmap (preview p)

-- | As per 'prismD' but fail the 'Decoder' if unsuccessful.
prismDOrFail
  :: Monad f
  => DecodeError
  -> Prism' a b
  -> Decoder f a
  -> Decoder f b
prismDOrFail e = prismDOrFail' (const e)

-- | Like 'prismDOrFail', but lets you use the @a@ to construct the error.
prismDOrFail'
  :: Monad f
  => (a -> DecodeError)
  -> Prism' a b
  -> Decoder f a
  -> Decoder f b
prismDOrFail' e p d = withCursor $
  focus d >=> Either.either (throwing _DecodeError . e) pure . matching p

-- | Decode an 'Int'.
int :: Monad f => Decoder f Int
int = integral

-- | Decode a 'Scientific' number value.
scientific :: Monad f => Decoder f Scientific
scientific = atCursor "scientific" DI.scientific'

-- | Decode a 'String' value.
string :: Monad f => Decoder f String
string = atCursor "string" DI.string'

-- | Decode a strict 'ByteString' value.
strictByteString :: Monad f => Decoder f ByteString
strictByteString = atCursor "strict bytestring" DI.strictByteString'

-- | Decode a lazy 'ByteString' value.
lazyByteString :: Monad f => Decoder f BL.ByteString
lazyByteString = atCursor "lazy bytestring" DI.lazyByteString'

-- | Decode a 'Char' value that is equivalent to a Haskell 'Char' value, as Haskell 'Char' supports a wider range than JSON.
unboundedChar :: Monad f => Decoder f Char
unboundedChar = atCursor "unbounded char" DI.unboundedChar'

-- | Decode a 'Char' that will fail if the 'Char' is outside of the range U+D800 to U+DFFF.
boundedChar :: Monad f => Decoder f Char
boundedChar = atCursor "bounded char" DI.boundedChar'

-- | Decode the 'Json' structure at the cursor. Useful if you don't have a need
-- to convert the Json and only want to make changes before sending it on its way.
json :: Monad f => Decoder f Json
json = atCursor "json" pure

-- | Decode 'Text'
text :: Monad f => Decoder f Text
text = atCursor "text" DI.text'

-- | Decode an explicit 'null' value at the current cursor position.
null :: Monad f => Decoder f ()
null = atCursor "null" DI.null'

-- | Decode a 'Bool' value.
bool :: Monad f => Decoder f Bool
bool = atCursor "bool" DI.bool'

-- | Given a 'Decoder' for @a@, attempt to decode a 'NonEmpty' list of @a@ at
-- the current cursor position.
nonemptyAt
  :: Monad f
  => Decoder f a
  -> JCurs
  -> DecodeResult f (NonEmpty a)
nonemptyAt elemD = withType JsonTypeArray $ down >=> \curs -> do
  h <- focus elemD curs
  DI.try (moveRight1 curs) >>= maybe
    (pure $ h :| [])
    (fmap (h :|) . rightwardSnoc [] elemD)

-- | Helper to create a 'NonEmpty a' 'Decoder'.
nonempty :: Monad f => Decoder f a -> Decoder f (NonEmpty a)
nonempty d = withCursor (nonemptyAt d)

-- | Like 'nonemptyAt', this takes a 'Decoder' of @a@ and at the given cursor
-- will try to decode a '[a]'.
listAt
  :: Monad f
  => Decoder f a
  -> JCurs
  -> DecodeResult f [a]
listAt elemD = withType JsonTypeArray $ \c ->
  DI.try (down c) >>= maybe (pure mempty) (rightwardSnoc mempty elemD)

-- | Helper function to simplify writing a '[]' decoder.
list :: Monad f => Decoder f a -> Decoder f [a]
list d = withCursor (listAt d)

-- | Try to decode an object using the given key and value 'Decoder's at the
-- given cursor.
objectAsKeyValuesAt
  :: Monad f
  => Decoder f k
  -> Decoder f v
  -> JCurs
  -> DecodeResult f [(k,v)]
objectAsKeyValuesAt keyD valueD = withType JsonTypeObject $ \curs ->
  DI.try (down curs) >>= maybe
    (pure mempty)
    (foldCursor snoc (moveRight1 >=> moveRight1) mempty (withCursor $ \c -> do
      k <- focus keyD c
      v <- moveRight1 c >>= focus valueD
      pure (k,v)
    ))

-- | Helper function to simplify writing a '{}' decoder.
objectAsKeyValues :: Monad f => Decoder f k -> Decoder f v -> Decoder f [(k,v)]
objectAsKeyValues k v = withCursor (objectAsKeyValuesAt k v)

-- | Try to decode an optional value, returning the given default value if
-- 'Nothing' is returned.
withDefault
  :: Monad f
  => a
  -> Decoder f (Maybe a)
  -> Decoder f a
withDefault def hasD =
  fromMaybe def <$> hasD

-- | Named to match it's 'Waargonaut.Encode.Encoder' counterpart, this function will decode an
-- optional value.
maybeOrNull
  :: Monad f
  => Decoder f a
  -> Decoder f (Maybe a)
maybeOrNull a =
  (Just <$> a) <!> (Nothing <$ null)

-- | Decode either an @a@ or a @b@, failing if neither 'Decoder' succeeds. The
-- 'Right' decoder is attempted first.
either
  :: Monad f
  => Decoder f a
  -> Decoder f b
  -> Decoder f (Either a b)
either leftD rightD =
  (Right <$> rightD) <!> (Left <$> leftD)
