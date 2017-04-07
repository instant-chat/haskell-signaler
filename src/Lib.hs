-- https://github.com/WeAreWizards/haskell-websockets-tsung-benchmark/blob/master/code/src/Main.hs

{-# LANGUAGE OverloadedStrings #-}
module Lib
    ( start
    ) where


import Prelude hiding (getContents, hGet, interact, scanl, foldl, concat, putStr, length, lookup)

import Control.Concurrent (forkIO, newEmptyMVar, newMVar, putMVar, readMVar, takeMVar, MVar)
import Control.Concurrent.Chan.Unagi (InChan, getChanContents, newChan, readChan, dupChan, writeChan, writeList2Chan)
import Control.Concurrent.Map (delete, empty, insert, lookup, Map)
import Control.Concurrent.Timer (repeatedTimer)
import Control.Concurrent.Suspend.Lifted (msDelay)
import Control.Exception
import Control.Monad (forever, when, void)
import qualified Data.ByteString.Lazy as BS (empty)
import Data.ByteString.Lazy (ByteString, concat, fromChunks, fromStrict, foldl, foldrChunks, getContents, putStr, hGet, interact, pack, scanl, toChunks, toStrict, unpack, length)
import Data.ByteString.Lazy.Builder (intDec, stringUtf8, toLazyByteString)
import Data.Either
import Data.Monoid (Monoid, mappend)
import Data.Text (Text)
import Numeric (showHex)
import Network.Wai.Handler.Warp (run, runSettings, setBeforeMainLoop, setLogger, setOnException, setOnClose, setOnOpen, setPort, setTimeout, defaultSettings)
import Network.Wai.Handler.WebSockets as WaiWS
import Network.WebSockets (acceptRequest, receiveData, receiveDataMessage, fromLazyByteString, send, sendTextData, PendingConnection, defaultConnectionOptions, DataMessage(..))
import Network.WebSockets.Connection (Connection)

import System.IO (hSetBuffering, isEOF, stdin, BufferMode( NoBuffering ))

(<>) :: Monoid a => a -> a -> a
(<>) = mappend


handleWS :: Map ByteString Connection -> PendingConnection -> IO ()
handleWS connections pending = do
    connection <- acceptRequest pending

    id <- newEmptyMVar
    partner <- newEmptyMVar

    putStrLn "listening"
    registerMessage <- receiveDataMessage connection
    register registerMessage id connection

    let loop = do
          message <- receiveDataMessage connection
          putStrLn "message"
          processMessage message id partner connection
          loop
    loop

    idString <- takeMVar id
    delete idString connections

    where
      register (Binary message) id connection = do
        putMVar id message
        insert message connection connections
        putStrLn ("Registering" ++ (prettyID message))

      processMessage (Text message) id partner connection = do
        putStrLn ("Text Message: " ++ (show message))

        partnerString <- readMVar partner
        print ("To" ++ (prettyID partnerString))

        partnerConnection <- lookup partnerString connections

        case partnerConnection of
          Just partnerConnection -> sendTextData partnerConnection message
          Nothing -> print "No partner"

      processMessage (Binary message) id partner connection = do
        putStrLn ("Binary Message (length): " ++ show (length message))
        putMVar partner message
        idString <- readMVar id
        putStrLn ((prettyID idString) ++ " selected " ++ (prettyID message))

      prettyID = show . unpack

      transmitMessage (Just partnerConnection) (Text message) = do
        print "msg"

      transmitMessage Nothing (Text message) = do
        print "no partner"


start :: IO ()
start = do
    putStrLn "Starting"

    hSetBuffering stdin NoBuffering

    connections <- empty

    connectionCount <- newMVar 0

    repeatedTimer (printStats connectionCount connections) (msDelay 5000)

    runSettings (
      ( setOnOpen (openHandler connectionCount)
      . setOnClose (closeHandler connectionCount)
      . setOnException (\_ e -> putStrLn ("Exception: " ++ show e))
      . setBeforeMainLoop (putStrLn "Listening on port 8080")
      . setLogger logger
      . setTimeout 60
      . setPort 8080) defaultSettings)
      $ WaiWS.websocketsOr defaultConnectionOptions (handleWS connections) undefined

      where
        closeHandler connectionCount addr = do
          count <- takeMVar connectionCount
          putMVar connectionCount (count - 1)
          print "Client Disconnected"

        openHandler connectionCount addr = do
          count <- takeMVar connectionCount
          putMVar connectionCount (count + 1)
          print "Client Connected"

          return True

        printStats connectionCount connections = do
          count <- readMVar connectionCount
          print count

        logger request status fileSize = do
          putStrLn ("does nothing" ++ (show status))