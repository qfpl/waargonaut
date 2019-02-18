module Waargonaut.Encode.Builder.JString (jStringBuilder) where

import           Waargonaut.Types.JString        (JString, JString' (..))

import           Waargonaut.Encode.Builder.JChar (jCharBuilder)
import           Waargonaut.Encode.Builder.Types (Builder (..))

-- $setup
-- >>> :set -XOverloadedStrings
-- >>> import Control.Lens ((#))
-- >>> import Control.Monad (return)
-- >>> import Data.Function (($))
-- >>> import Data.Either(Either (..), isLeft)
-- >>> import Data.Digit (HeXDigit(..))
-- >>> import qualified Data.Vector as V
-- >>> import Utils
-- >>> import Waargonaut.Decode.Error (DecodeError)
-- >>> import Waargonaut.Types.Whitespace
-- >>> import Waargonaut.Types.JChar.Unescaped
-- >>> import Waargonaut.Types.JChar.Escaped
-- >>> import Waargonaut.Types.JChar.HexDigit4
-- >>> import Waargonaut.Types.JChar
-- >>> import Data.Text.Lazy.Builder (toLazyText)
----

-- | Builder for a 'JString'.
--
-- >>> toLazyText $ jStringBuilder ((JString' V.empty) :: JString)
-- "\"\""
--
-- >>> toLazyText $ jStringBuilder ((JString' $ V.fromList [UnescapedJChar (Unescaped 'a'),UnescapedJChar (Unescaped 'b'),UnescapedJChar (Unescaped 'c')]) :: JString)
-- "\"abc\""
--
-- >>> toLazyText $ jStringBuilder ((JString' $ V.fromList [UnescapedJChar (Unescaped 'a'),EscapedJChar (WhiteSpace CarriageReturn),UnescapedJChar (Unescaped 'b'),UnescapedJChar (Unescaped 'c')]) :: JString)
-- "\"a\\rbc\""
--
-- >>> toLazyText $ jStringBuilder ((JString' $ V.fromList [UnescapedJChar (Unescaped 'a'),EscapedJChar (WhiteSpace CarriageReturn),UnescapedJChar (Unescaped 'b'),UnescapedJChar (Unescaped 'c'),EscapedJChar (Hex (HexDigit4 HeXDigita HeXDigitb HeXDigit1 HeXDigit2)),EscapedJChar (WhiteSpace NewLine),UnescapedJChar (Unescaped 'd'),UnescapedJChar (Unescaped 'e'),UnescapedJChar (Unescaped 'f'),EscapedJChar QuotationMark]) :: JString)
-- "\"a\\rbc\\uab12\\ndef\\\"\""
--
-- >>> toLazyText $ jStringBuilder ((JString' $ V.singleton (UnescapedJChar (Unescaped 'a'))) :: JString)
-- "\"a\""
--
-- >>> toLazyText $ jStringBuilder (JString' $ V.singleton (EscapedJChar ReverseSolidus) :: JString)
-- "\"\\\\\""
--
jStringBuilder
  :: Monoid b
  => Builder t b
  -> JString
  -> b
jStringBuilder bldr (JString' jcs) =
  fromChar bldr '\"' <> foldMap (jCharBuilder bldr) jcs <> fromChar bldr '\"'
