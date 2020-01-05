const socket_path = '/tmp/node-inspect.sock';
const net = require('net');
var EventEmitter = require('events').EventEmitter;
const PORT = 9514;


class NvimBridge {

	constructor() {
		this.notifier = new EventEmitter();
		this.client = null;
		this.server = null;
		this.callback = null;
	}

	send(msg) {
		if (this.client) {
			// console.log("=> sending msg",msg);
			this.client.write(JSON.stringify(msg));
		}
		else {
			console.error("can't send event, vim object not setup");
		}
	}

	setEventCallback(callback) {
		this.callback = callback;
	}


	createServer() {
		return new Promise((resolve,reject) => {
			// This server listens on a Unix socket at /var/run/mysocket
			this.server = net.createServer((client) => {
				this.client = client;
				// I'll resolve only when a client connects
				resolve();
				// single client support at this time
				this.client.on('data', (data) => {
					//console.log('client says',data.toString(), typeof(data));
					if (this.callback) {
						let message = data.toString();
						let json = JSON.parse(message);
						this.callback(json);
					}
				});
			});
			this.server.listen(PORT, (c) => {
			});
		});
	}
}

module.exports = NvimBridge;