"use strict";

// Mico | Sem restricao de chat

const MAX_CHAT_LENGTH = 500;

const tidy = text => {
  return String(text ?? "")
    .slice(0, MAX_CHAT_LENGTH)
    .trim();
};

const repeated = () => false;

module.exports = {
  tidy,
  repeated
};