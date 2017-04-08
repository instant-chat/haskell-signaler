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
import Network.WebSockets (acceptRequest, forkPingThread, receiveData, receiveDataMessage, fromLazyByteString, send, sendTextData, PendingConnection, defaultConnectionOptions, DataMessage(..))
import Network.WebSockets.Connection (Connection)

import System.IO (hSetBuffering, isEOF, stdin, BufferMode( NoBuffering ))

(<>) :: Monoid a => a -> a -> a
(<>) = mappend


handleWS :: Map ByteString Connection -> PendingConnection -> IO ()
handleWS connections pending = do
    connection <- acceptRequest pending

    forkPingThread connection 55

    handle connection

    where
      handle connection = do

        id <- newEmptyMVar
        partner <- newEmptyMVar

        idMessage <- receiveDataMessage connection
        register idMessage connection id

        let loop = do
              message <- receiveDataMessage connection
              print "Message received"
              processMessage message connection id partner
              loop
        loop

        idString <- takeMVar id
        delete idString connections

        where
          register (Binary message) connection id = do
            putMVar id message
            insert message connection connections
            print ("Registering" ++ (prettyID message))

          processMessage (Text message) connection id partner = do
            print ("Text Message: " ++ (show message))

            partnerString <- readMVar partner

            print ("To" ++ (prettyID partnerString))

            partnerConnection <- lookup partnerString connections

            case partnerConnection of
              Just partnerConnection -> sendTextData partnerConnection message
              Nothing -> print "No partner" -- should search larger network in this case

          processMessage (Binary message) connection id partner = do
            print ("Binary Message (length): " ++ show (length message))
            putMVar partner message
            idString <- readMVar id
            print ((prettyID idString) ++ " selected " ++ (prettyID message))

          prettyID = show . unpack


start :: IO ()
start = do
    print "Starting"

    connections <- empty

    connectionCount <- newMVar 0

    repeatedTimer (printStats connectionCount connections) (msDelay 5000)

    runSettings (
      ( setOnOpen (openHandler connectionCount)
      . setOnClose (closeHandler connectionCount)
      . setOnException (\_ e -> print ("Exception: " ++ show e))
      . setBeforeMainLoop (print "Listening on port 8080")
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
          print ("Logger: " ++ (show status) ++ (show fileSize))