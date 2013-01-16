{-# OPTIONS_GHC -funbox-strict-fields #-}

{-# LANGUAGE BangPatterns #-}

-- |
-- Module    : Data.BitVector
-- Copyright : (c) Iago Abal, 2012-2013
--             (c) University of Minho, 2012
-- License   : BSD3
-- Maintainer: Iago Abal <iago.abal@gmail.com>
--
-- Implementation of bit-vectors as wrappers over 'Integer'.
--
-- * Bit-vectors are interpreted as unsigned integers
--   (i.e. natural numbers) except for some very specific cases.
--
-- * Bit-vectors are /size-polymorphic/ insofar as most operations treat
--   a bit-vector of size /n/ as of size /m/ for /m >= n/ if required.
--
-- For documentation purposes we will write @[n]k@ to denote a bit-vector
-- of size @n@ representing the natural number @k@.
module Data.BitVector
  ( -- * Bit-vectors
    BitVector
  , BV
  , size, width
  , nat, uint, int
    -- * Creation
  , bitVec
  , ones, zeros
    -- * Comparison
  , (==.), (/=.)
  , (<.), (<=.), (>.), (>=.)
  , slt, sle, sgt, sge
    -- * Indexing
  , (@.), index
  , (@@), extract
  , (!.)
  , least, most
  , msb, lsb, msb1
  -- * Arithmetic
  , sdiv, srem, smod
  , lg2
  -- * List-like operations
  , (#), cat
  , zeroExtend, signExtend
  , foldl_, foldr_
  , reverse_
  , replicate_
  , and_, or_
  , split, group_, join
  -- * Bitwise operations
  , module Data.Bits
  , not_, nand, nor, xnor
  , (<<.), shl, (>>.), shr, ashr
  , (<<<.), rol, (>>>.), ror
  -- * Conversion
  , fromBool
  , fromBits
  , toBits
  -- * Pretty-printing
  , showBin
  , showOct
  , showHex
  -- * Utilities
  , maxNat
  , integerWidth
  ) where

import Control.Exception ( assert )

import Data.Bits
import Data.List ( foldl1' )
import Data.Ord
import Data.Typeable ( Typeable(..), mkTyConApp, mkTyCon3 )
import Data.Data
  ( Data(..), Fixity(Prefix)
  , constrIndex, indexConstr, mkDataType, mkConstr
  )

----------------------------------------------------------------------
--- Bit-vectors

-- | Big-endian /pseudo size-polymorphic/ bit-vectors.
data BV
    = BV {
      size :: !Int      -- ^ The /size/ of a bit-vector.
    , nat  :: !Integer  -- ^ The value of a bit-vector, as a natural number.
    }

-- | An alias for 'BV'.
type BitVector = BV

-- | An alias for 'size'.
width :: BV -> Int
width = size
{-# INLINE width #-}

-- | An alias for 'nat'.
uint :: BV -> Integer
uint = nat
{-# INLINE uint #-}

-- | 2's complement value of a bit-vector.
int :: BV -> Integer
int u | msb u     = - nat(-u)
      | otherwise = nat u

instance Show BV where
  show (BV n a) = "[" ++ show n ++ "]" ++ show a

instance Typeable BV where
  typeOf _ = mkTyConApp bvTyCon []
    where bvTyCon = mkTyCon3 "bv" "Data.BitVector" "BV"

instance Data BV where
  gfoldl k r (BV x1 x2) = r BV `k` x1 `k` x2
  gunfold k z c
    = case constrIndex c - 1 of
          0 -> k $ k $ z BV
          i -> error $ "Data.gunfold for BV, unknown index: " ++ show i
  toConstr x@BV{} = indexConstr (dataTypeOf x) 1
  dataTypeOf _ = ty
    where ty = mkDataType "Data.BitVector.BV"
                  [mkConstr ty "BV" ["size", "nat"] Prefix]

----------------------------------------------------------------------
--- Construction

-- | Create a bit-vector given a size and an integer value.
--
-- >>> bitVec 4 3
-- [4]3
--
-- This function also handles negative values.
--
-- >>> bitVec 4 (-1)
-- [4]15
bitVec :: Integral a => Int -> a -> BV
bitVec n a | a >= 0    = BV n $ fromIntegral a
           | otherwise = negate $ BV n $ fromIntegral (-a)
{-# RULES "bitVec/Integer" bitVec = BV #-}
{-# SPECIALIZE bitVec :: Int -> Int -> BV #-}
{-# INLINE[1] bitVec #-}

-- | Create a mask of ones.
ones :: Int -> BV
ones n = BV n $ 2^n - 1
{-# INLINE ones #-}

-- | Create a mask of zeros.
zeros :: Int -> BV
zeros n = BV n 0
{-# INLINE zeros #-}

----------------------------------------------------------------------
--- Comparison

instance Eq BV where
  (BV _ a) == (BV _ b) = a == b

instance Ord BV where
  compare = comparing nat

-- | Fixed-size equality.
--
-- In contrast with '==', which is /size-polymorphic/, this equality
-- requires both bit-vectors to be of equal size.
--
-- >>> [n]k ==. [m]k
-- False
--
-- >>> [n]k ==. [n]k
-- True
(==.) :: BV -> BV -> Bool
(BV n a) ==. (BV m b) = n == m && a == b

-- | Fixed-size inequality.
--
-- The negated version of '==.'.
(/=.) :: BV -> BV -> Bool
u /=. v = not $ u ==. v
{-# INLINE (/=.) #-}

-- | Fixed-size /less-than/.
(<.) :: BV -> BV -> Bool
(BV n a) <. (BV m b) = n == m && a < b
{-# INLINE (<.) #-}

-- | Fixed-size /less-than-or-equals/.
(<=.) :: BV -> BV -> Bool
(BV n a) <=. (BV m b) = n == m && a <= b
{-# INLINE (<=.) #-}

-- | Fixed-size /greater-than/.
(>.) :: BV -> BV -> Bool
(BV n a) >. (BV m b) = n == m && a > b
{-# INLINE (>.) #-}

-- | Fixed-size /greater-than-or-equals/.
(>=.) :: BV -> BV -> Bool
(BV n a) >=. (BV m b) = n == m && a >= b
{-# INLINE (>=.) #-}

-- | Fixed-size signed /less-than/.
slt :: BV -> BV -> Bool
u@BV{size=n} `slt` v@BV{size=m} = n == m && int u < int v
{-# INLINE slt #-}

-- | Fixed-size signed /less-than-or-equals/.
sle :: BV -> BV -> Bool
u@BV{size=n} `sle` v@BV{size=m} = n == m && int u <= int v
{-# INLINE sle #-}

-- | Fixed-size signed /greater-than/.
sgt :: BV -> BV -> Bool
u@BV{size=n} `sgt` v@BV{size=m} = n == m && int u > int v
{-# INLINE sgt #-}

-- | Fixed-size signed /greater-than-or-equals/.
sge :: BV -> BV -> Bool
u@BV{size=n} `sge` v@BV{size=m} = n == m && int u >= int v
{-# INLINE sge #-}

----------------------------------------------------------------------
--- Indexing

-- | Bit indexing.
--
-- @u \@. i@ stands for the /i/-th bit of /u/.
--
-- >>> [4]2 @. 0
-- False
--
-- >>> [4]2 @. 1
-- True
(@.) :: Integral ix => BV -> ix -> Bool
(BV _ a) @. i = testBit a (fromIntegral i)
{-# SPECIALIZE (@.) :: BV -> Int     -> Bool #-}
{-# SPECIALIZE (@.) :: BV -> Integer -> Bool #-}
{-# INLINE[1] (@.) #-}

-- | @index i a == a \@. i@
index :: Integral ix => ix -> BV -> Bool
index = flip (@.)
{-# INLINE index #-}

-- | Bit-string extraction.
--
-- @u \@\@ (j,i) == fromBits (map (u \@.) [j,j-1..i])@
--
-- >>> [4]7 @@ (3,1)
-- [3]3
(@@) :: Integral ix => BV -> (ix,ix) -> BV
(BV _ a) @@ (j,i) = assert (i >= 0 && j >= i) $
    BV m $ (a `shiftR` i') `mod` 2^m
  where i' = fromIntegral i
        m  = fromIntegral $ j - i + 1
{-# SPECIALIZE (@@) :: BV -> (Int,Int)         -> BV #-}
{-# SPECIALIZE (@@) :: BV -> (Integer,Integer) -> BV #-}

-- | @extract j i a == a \@\@ (j,i)@
extract :: Integral ix => ix -> ix -> BV -> BV
extract j i = (@@ (j,i))
{-# INLINE extract #-}

-- | Reverse bit-indexing.
--
-- Index starting from the most significant bit.
--
-- @u !. i == u \@. (size u - i - 1) @
--
-- >>> [3]3 !. 0
-- False
(!.) :: Integral ix => BV -> ix -> Bool
(BV n a) !. i = assert (i' < n) $ testBit a (n-i'-1)
  where i' = fromIntegral i
{-# SPECIALIZE (!.) :: BV -> Int     -> Bool #-}
{-# SPECIALIZE (!.) :: BV -> Integer -> Bool #-}
{-# INLINE[1] (!.) #-}

-- | Take least significant bits.
--
-- @least m u == u \@\@ (m-1,0)@
least :: Integral ix => ix -> BV -> BV
least m (BV _ a) = assert (m >= 1) $
  BV m' $ a `mod` 2^m
  where m' = fromIntegral m
{-# SPECIALIZE least :: Int     -> BV -> BV #-}
{-# SPECIALIZE least :: Integer -> BV -> BV #-}

-- | Take most significant bits.
--
-- @most m u == u \@\@ (n-1,n-m)@
most :: Integral ix => ix -> BV -> BV
most m (BV n a) = assert (m' >= 1 && m' <= n) $
  BV m' $ a `shiftR` (n-m')
  where m' = fromIntegral m
{-# SPECIALIZE most :: Int     -> BV -> BV #-}
{-# SPECIALIZE most :: Integer -> BV -> BV #-}

-- | Most significant bit.
--
-- @msb u == u !. 0@
msb :: BV -> Bool
msb = (!. (0::Int))
{-# INLINE msb #-}

-- | Least significant bit.
--
-- @lsb u == u \@. 0@
lsb :: BV -> Bool
lsb = (@. (0::Int))
{-# INLINE lsb #-}

-- | Most significant 1-bit.
--
-- /Pre/: input must be non-zero.
--
-- >>> msb1 [4]2
-- 1
--
-- >>> msb1 [4]4
-- 2
msb1 :: BV -> Int
msb1 (BV _ 0) = error "Data.BitVector.msb1: zero bit-vector"
msb1 (BV n a) = go (n-1)
  where go i | testBit a i = i
             | otherwise   = go (i-1)

----------------------------------------------------------------------
--- Arithmetic

instance Num BV where
  (BV n1 a) + (BV n2 b) = BV n $ (a + b) `mod` 2^n
    where n = max n1 n2
  (BV n1 a) * (BV n2 b) = BV n $ (a * b) `mod` 2^n
    where n = max n1 n2
  negate (BV n a) = BV n $ 2^n - a
  abs u | msb u     = negate u
        | otherwise = u
  signum u = bitVec 2 $ int u
  fromInteger i = bitVec (integerWidth i) i

instance Real BV where
  toRational = toRational . nat

instance Enum BV where
  toEnum = fromIntegral
  fromEnum (BV _ a) = assert (a < max_int) $ fromIntegral a
    where max_int = toInteger (maxBound::Int)

instance Integral BV where
  quotRem (BV n1 a) (BV n2 b) = (BV n q,BV n r)
    where n = max n1 n2
          (q,r) = quotRem a b
  divMod = quotRem
  toInteger = nat

-- | 2's complement signed division.
sdiv :: BV -> BV -> BV
sdiv u@(BV n1 _) v@(BV n2 _) = bitVec n q
  where n = max n1 n2
        q = int u `quot` int v

-- | 2's complement signed remainder (sign follows dividend).
srem :: BV -> BV -> BV
srem u@(BV n1 _) v@(BV n2 _) = bitVec n r
  where n = max n1 n2
        r = int u `rem` int v

-- | 2's complement signed remainder (sign follows divisor).
smod :: BV -> BV -> BV
smod u@(BV n1 _) v@(BV n2 _) = bitVec n r
  where n = max n1 n2
        r = int u `mod` int v

-- | Ceiling logarithm base 2.
--
-- /Pre/: input bit-vector must be non-zero.
lg2 :: BV -> BV
lg2 (BV _ 0) = error "Data.BitVector.lg2: zero bit-vector"
lg2 (BV n 1) = BV n 0
lg2 (BV n a) = BV n $ toInteger $ integerWidth (a-1)

----------------------------------------------------------------------
--- List-like operations

-- | Concatenation of two bit-vectors.
(#), cat :: BV -> BV -> BV
(BV n a) # (BV m b) = BV (n + m) ((a `shiftL` m) + b)
{-# INLINABLE (#) #-}

cat = (#)
{-# INLINE cat #-}

-- | Logical extension.
--
-- >>> zeroExtend 3 [1]1
-- [4]1
zeroExtend :: Integral size => size -> BV -> BV
zeroExtend d (BV n a) = BV (n+d') a
  where d' = fromIntegral d
{-# SPECIALIZE zeroExtend :: Int     -> BV -> BV #-}
{-# SPECIALIZE zeroExtend :: Integer -> BV -> BV #-}
{-# INLINE[1] zeroExtend #-}

-- | Arithmetic extension.
--
-- >>> signExtend 2 [2]1
-- [4]1
--
-- >>> signExtend 2 [2]3
-- [4]15
signExtend :: Integral size => size -> BV -> BV
signExtend d (BV n a)
  | testBit a (n-1) = BV (n+d') $ (maxNat d `shiftL` n) + a
  | otherwise       = BV (n+d') a
  where d' = fromIntegral d
{-# SPECIALIZE signExtend :: Int     -> BV -> BV #-}
{-# SPECIALIZE signExtend :: Integer -> BV -> BV #-}
{-# INLINE[1] signExtend #-}

-- |
-- @foldl_ f z (fromBits [un, ..., u1, u0]) == ((((z \`f\` un) \`f\` ...) \`f\` u1) \`f\` u0)@
--
-- @foldl_ f e = fromBits . foldl f e . toBits@
foldl_ :: (a -> Bool -> a) -> a -> BV -> a
foldl_ f e (BV n a) = go (n-1) e
  where go i !x | i >= 0    = let !b = testBit a i in go (i-1) $ f x b
                | otherwise = x
{-# INLINE foldl_ #-}

-- |
-- @foldr_ f z (fromBits [un, ..., u1, u0]) == un \`f\` (... \`f\` (u1 \`f\` (u0 \`f\` z)))@
--
-- @foldr_ f e = fromBits . foldr f e . toBits@
foldr_ :: (Bool -> a -> a) -> a -> BV -> a
foldr_ f e (BV n a) = go (n-1) e
 where go i !x | i >= 0    = let !b = testBit a i in f b (go (i-1) x)
               | otherwise = x
{-# INLINE foldr_ #-}

-- |
-- @reverse_ == fromBits . reverse . toBits@
reverse_ :: BV -> BV
reverse_ bv@(BV n _) = BV n $ snd $ foldl_ go (1,0) bv
  where go (v,acc) b | b         = (v',acc+v)
                     | otherwise = (v',acc)
          where v' = 2*v

-- |
-- /Pre/: if @replicate_ n u@ then @n > 0@ must hold.
--
-- @replicate_ n == fromBits . concat . replicate n . toBits @
replicate_ :: Integral size => size -> BV -> BV
replicate_ 0 _ = error "Data.BitVector.replicate_: cannot replicate 0-times"
replicate_ n u = go (n-1) u
  where go 0 !acc = acc
        go k !acc = go (k-1) (u # acc)
{-# SPECIALIZE replicate_ :: Int     -> BV -> BV #-}
{-# SPECIALIZE replicate_ :: Integer -> BV -> BV #-}

-- | Conjunction.
--
-- @and_ == foldr1 (.&.)@
and_ :: [BV] -> BV
and_ [] = error "Data.BitVector.and_: empty list"
and_ ws = BV n' $ foldl1' (.&.) $ map nat ws
  where n' = maximum $ map size ws
{-# INLINE and_ #-}

-- | Disjunction.
--
-- @or_ == foldr1 (.|.)@
or_ :: [BV] -> BV
or_ [] = error "Data.BitVector.or_: empty list"
or_ ws = BV n' $ foldl1' (.|.) $ map nat ws
  where n' = maximum $ map size ws
{-# INLINE or_ #-}

-- | Split a bit-vector /k/ times.
--
-- >>> split 3 [4]15
-- [[2]0,[2]3,[2]3]
split :: Integral times => times -> BV -> [BV]
split k (BV n a) = assert (k > 0) $
  map (BV s) $ splitInteger s k' a
  where k' = fromIntegral k
        (q,r) = divMod n k'
        s = q + signum r

-- | Split a bit-vector into /n/-wide pieces.
--
-- >>> group_ 3 [4]15
-- [[3]1,[3]7]
group_ :: Integral size => size -> BV -> [BV]
group_ s (BV n a) = assert (s > 0) $
  map (BV s') $ splitInteger s' k a
  where s' = fromIntegral s
        (q,r) = divMod n s'
        k = q + signum r

splitInteger :: (Integral size, Integral times) =>
                    size -> times -> Integer -> [Integer]
splitInteger n = go []
  where n' = fromIntegral n
        go acc 0 _ = acc
        go acc k a = go (v:acc) (k-1) a'
          where v  = a `mod` 2^n
                a' = a `shiftR` n'
{-# SPECIALIZE splitInteger :: Int     -> Int     -> Integer -> [Integer] #-}
{-# SPECIALIZE splitInteger :: Integer -> Integer -> Integer -> [Integer] #-}
{-# INLINE[1] splitInteger #-}

-- | Concatenate a list of bit-vectors.
--
-- >>> join [[2]3,[2]2]
-- [4]14
join :: [BV] -> BV
join = foldl1' (#)

----------------------------------------------------------------------
--- Bitwise operations

instance Bits BV where
  (BV n1 a) .&. (BV n2 b) = BV n $ a .&. b
    where n = max n1 n2
  (BV n1 a) .|. (BV n2 b) = BV n $ a .|. b
    where n = max n1 n2
  (BV n1 a) `xor` (BV n2 b) = BV n $ a `xor` b
    where n = max n1 n2
  complement (BV n a) = BV n $ 2^n - 1 - a
  bit i = BV (i+1) (2^i)
  testBit (BV n a) i | i < n     = testBit a i
                     | otherwise = False
  bitSize = undefined
  isSigned = const False
  shiftL (BV n a) k
    | k > n     = BV n 0
    | otherwise = BV n $ shiftL a k `mod` 2^n
  shiftR (BV n a) k
    | k > n     = BV n 0
    | otherwise = BV n $ shiftR a k
  rotateL bv       0 = bv
  rotateL (BV n a) k
    | k == n    = BV n a
    | k > n     = rotateL (BV n a) (k `mod` n)
    | otherwise = BV n $ h + l
    where s = n - k
          l = a `shiftR` s
          h = (a `shiftL` k) `mod` 2^n
  rotateR bv       0 = bv
  rotateR (BV n a) k
    | k == n    = BV n a
    | k > n     = rotateR (BV n a) (k `mod` n)
    | otherwise = BV n $ h + l
    where s = n - k
          l = a `shiftR` k
          h = (a `shiftL` s) `mod` 2^n

-- | An alias for 'complement'.
not_ :: BV -> BV
not_ = complement
{-# INLINE not_ #-}

-- | Negated '.&.'.
nand :: BV -> BV -> BV
nand u v = not_ $ u .&. v
{-# INLINE nand #-}

-- | Negated '.|.'.
nor :: BV -> BV -> BV
nor u v = not_ $ u .|. v
{-# INLINE nor #-}

-- | Negated 'xor'.
xnor :: BV -> BV -> BV
xnor u v = not_ $ u `xor` v
{-# INLINE xnor #-}

-- | Left shift.
(<<.), shl :: BV -> BV -> BV
bv@BV{size=n} <<. (BV _ k)
  | k >= fromIntegral n  = BV n 0
  | otherwise            = bv `shiftL` (fromIntegral k)
{-# INLINE (<<.) #-}

shl = (<<.)
{-# INLINE shl #-}

-- | Logical right shift.
(>>.), shr :: BV -> BV -> BV
bv@BV{size=n} >>. (BV _ k)
  | k >= fromIntegral n  = BV n 0
  | otherwise            = bv `shiftR` (fromIntegral k)
{-# INLINE (>>.) #-}

shr = (>>.)
{-# INLINE shr #-}

-- | Arithmetic right shift
ashr :: BV -> BV -> BV
ashr u v | msb u     = not_ ((not_ u) >>. v)
         | otherwise = u >>. v

-- | Rotate left.
(<<<.), rol :: BV -> BV -> BV

bv@BV{size=n} <<<. (BV _ k)
  | k >= n'   = bv `rotateL` (fromIntegral $ k `mod` n')
  | otherwise = bv `rotateL` (fromIntegral k)
  where n' = fromIntegral n
{-# INLINE (<<<.) #-}

rol = (<<<.)
{-# INLINE rol #-}

-- | Rotate right.
(>>>.), ror :: BV -> BV -> BV

bv@BV{size=n} >>>. (BV _ k)
  | k >= n'   = bv `rotateR` (fromIntegral $ k `mod` n')
  | otherwise = bv `rotateR` (fromIntegral k)
  where n' = fromIntegral n
{-# INLINE (>>>.) #-}

ror = (>>>.)
{-# INLINE ror #-}

----------------------------------------------------------------------
--- Conversion

-- | Create a bit-vector from a single bit.
fromBool :: Bool -> BV
fromBool False = BV 1 0
fromBool True  = BV 1 1
{-# INLINE fromBool #-}

-- | Create a bit-vector from a big-endian list of bits.
--
-- >>> fromBits [False, False, True]
-- [3]1
fromBits :: [Bool] -> BV
fromBits bs = BV n $ snd $ foldr go (1,0) bs
  where n = length bs
        go b (!v,!acc) | b         = (v',acc+v)
                       | otherwise = (v',acc)
          where v' = 2*v

-- | Create a big-endian list of bits from a bit-vector.
--
-- >>> toBits [4]11
-- [True, False, True, True]
toBits :: BV -> [Bool]
toBits (BV n a) = map (testBit a) [n-1,n-2..0]

----------------------------------------------------------------------
--- Pretty-printing

-- | Show a bit-vector in binary form.
showBin :: BV -> String
showBin = ("0b" ++) . map showBit . toBits
  where showBit True  = '1'
        showBit False = '0'

hexChar :: Integral a => a -> Char
hexChar 0 = '0'
hexChar 1 = '1'
hexChar 2 = '2'
hexChar 3 = '3'
hexChar 4 = '4'
hexChar 5 = '5'
hexChar 6 = '6'
hexChar 7 = '7'
hexChar 8 = '8'
hexChar 9 = '9'
hexChar 10 = 'a'
hexChar 11 = 'b'
hexChar 12 = 'c'
hexChar 13 = 'd'
hexChar 14 = 'e'
hexChar 15 = 'f'
hexChar _  = error "Data.BitVector.hexChar: invalid input"

-- | Show a bit-vector in octal form.
showOct :: BV -> String
showOct = ("0o" ++) . map (hexChar . nat) . group_ (3::Int)

-- | Show a bit-vector in hexadecimal form.
showHex :: BV -> String
showHex = ("0x" ++) . map (hexChar . nat) . group_ (4::Int)

----------------------------------------------------------------------
--- Utilities

-- | Greatest natural number representable with /n/ bits.
maxNat :: (Integral a, Integral b) => a -> b
maxNat n = 2^n - 1
{-# INLINE maxNat #-}

-- | Minimum width of a bit-vector to represent a given integer number.
--
-- >>> integerWith 4
-- 3
--
-- >>> integerWith (-4)
-- 4
integerWidth :: Integer -> Int
integerWidth !n
  | n >= 0    = go 1 1
  | otherwise = 1 + integerWidth (abs n)
  where go !k !k_max | k_max >= n = k
                     | otherwise  = go (k+1) (2*k_max+1)
{-# INLINE integerWidth #-}
