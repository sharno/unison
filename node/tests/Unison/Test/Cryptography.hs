{-# LANGUAGE OverloadedStrings #-}
module Unison.Test.Cryptography where

import EasyTest
import Control.Monad
import Control.Monad.STM
import qualified Unison.Cryptography as C
import qualified Crypto.PubKey.ECC.ECDSA as ECDSA
import Unison.Runtime.Cryptography
import qualified Data.ByteString as B
import Crypto.Noise.DH
import Crypto.Noise.DH.Curve25519

testEncryptDecrypt :: Test ()
testEncryptDecrypt = do
  keyPair <- io (dhGenKey :: IO (KeyPair Curve25519))
  let crypto = mkCrypto keyPair
  Just symkey <- symmetricKey <$> io (C.randomBytes crypto 32)
  bigSizes <- listOf 3 (int' 1000 9000)
  cleartexts <- map B.pack <$> listsOf ([0..100] ++ bigSizes) word8
  cleartexts `forM_` \cleartext -> do
    ciphertext <- io (C.encrypt crypto symkey [cleartext])
    let cleartext' = C.decrypt crypto symkey ciphertext
    case cleartext' of
      Left err -> crash err
      Right cleartext' -> expect (cleartext == cleartext')

testPipe :: Test ()
testPipe = do
  ikp <- io (dhGenKey :: IO (KeyPair Curve25519)) -- initiator key pair
  rkp <- io (dhGenKey :: IO (KeyPair Curve25519)) -- responder key pair
  let initiator = mkCrypto ikp :: C.Cryptography (PublicKey Curve25519) SymmetricKey ECDSA.PublicKey ECDSA.PrivateKey () B.ByteString B.ByteString
      responder = mkCrypto rkp :: C.Cryptography (PublicKey Curve25519) SymmetricKey ECDSA.PublicKey ECDSA.PrivateKey () B.ByteString B.ByteString
      rpk = snd rkp -- remote public key
  (doneHandshake, iencrypt, idecrypt) <- io $ C.pipeInitiator initiator rpk
  (_, _, rencrypt, rdecrypt) <- io $ C.pipeResponder responder
  bigSizes <- listOf 3 (int' 1000 9000)
  cleartexts <- map B.pack <$> listsOf ([0..100] ++ bigSizes) word8
  cleartexts `forM_` \cleartext -> do
    go doneHandshake cleartext iencrypt idecrypt rencrypt rdecrypt
  where
    go doneHandshake plaintext iencrypt idecrypt rencrypt rdecrypt = do
      ready <- io $ atomically doneHandshake
      case ready of
        True -> do
          ciphertext <- io $ atomically $ iencrypt plaintext
          plaintext' <- io $ atomically $ rdecrypt ciphertext
          expect (plaintext == plaintext')
        False -> do
          ciphertext <- io $ atomically $ iencrypt ""
          plaintext' <- io $ atomically $ rdecrypt ciphertext
          ciphertextr <- io $ atomically $ rencrypt ""
          plaintextr' <- io $ atomically $ idecrypt ciphertextr
          expect ("" == plaintext')
          expect ("" == plaintextr')
          go doneHandshake plaintext iencrypt idecrypt rencrypt rdecrypt

test :: Test ()
test = scope "Crypto" $
  tests [ scope "encrypt/decrypt roundtrip" testEncryptDecrypt
        , scope "Pipes roundtrip" testPipe
        ]
