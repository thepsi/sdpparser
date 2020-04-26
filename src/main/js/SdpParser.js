var generated = require("./GeneratedParser");
var utils = require("./utils");

module.exports = {
  SyntaxError: generated.SyntaxError,
  parse: generated.parse,
  format: utils.formatSdp,
};
