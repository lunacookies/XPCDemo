#include <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <os/log.h>
#include <stdio.h>
#include <time.h>
#include <xpc/xpc.h>

os_log_t Log;

void IncomingMessageHandler(xpc_object_t message) {
	os_log_info(Log, "got message from service, not doing anything...");
	os_log_info(Log, "message: %s", xpc_copy_description(message));
}

xpc_object_t CreateMessage(NSData *bookmark) {
	xpc_object_t message = xpc_dictionary_create_empty();

	xpc_dictionary_set_value(message, "msg", xpc_string_create("hellooooo"));

	xpc_object_t bookmarkXPCData = xpc_data_create(bookmark.bytes, bookmark.length);
	xpc_dictionary_set_value(message, "bookmark", bookmarkXPCData);

	os_log_info(Log, "created message: %s", xpc_copy_description(message));
	return message;
}

int main() {
	Log = os_log_create("org.xoria.XPCDemo", "main");
	NSError *e = nil;

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSURL *desktop = [fileManager URLForDirectory:NSDesktopDirectory
	                                     inDomain:NSUserDomainMask
	                            appropriateForURL:nil
	                                       create:YES
	                                        error:&e];
	if (desktop == nil) {
		os_log_error(Log, "failed to locate user’s Desktop: %@", e.localizedDescription);
		return 1;
	}

	NSURL *secretURL = [desktop URLByAppendingPathComponent:@"secret" isDirectory:NO];
	NSURL *bookmarkURL = [desktop URLByAppendingPathComponent:@"bookmark" isDirectory:NO];

	NSString *secret = [NSString stringWithContentsOfURL:secretURL
	                                            encoding:NSUTF8StringEncoding
	                                               error:&e];
	if (secret == nil) {
		os_log_error(
		        Log, "failed to read secret at %@: %@", secretURL, e.localizedDescription);
		return 1;
	}

	os_log_info(Log, "secret is %@", secret);

	NSData *bookmark = [secretURL bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
	                       includingResourceValuesForKeys:[NSArray array]
	                                        relativeToURL:nil
	                                                error:&e];
	if (bookmark == nil) {
		os_log_error(Log, "failed to create bookmark for %@: %@", secretURL,
		        e.localizedDescription);
		return 1;
	}

	os_log_info(Log, "writing bookmark data to file at %@", bookmarkURL);
	BOOL didWrite = [bookmark writeToURL:bookmarkURL options:0 error:&e];
	if (!didWrite) {
		os_log_error(Log, "failed to write bookmark: %@", e.localizedDescription);
		return 1;
	}

	BOOL isStale = NO;
	NSURL *URLFromBookmark = [NSURL URLByResolvingBookmarkData:bookmark
	                                                   options:NSURLBookmarkResolutionWithoutUI
	                                             relativeToURL:nil
	                                       bookmarkDataIsStale:&isStale
	                                                     error:&e];

	if (URLFromBookmark == nil) {
		os_log_error(Log, "failed to resolve bookmark: %@", e.localizedDescription);
		return 1;
	}

	if (isStale) {
		os_log_info(Log, "bookmark resolving to %@ was stale!", URLFromBookmark);
	}

	os_log_info(Log, "resolved bookmark to URL: %@", URLFromBookmark);

	xpc_rich_error_t error = NULL;
	dispatch_queue_t queue =
	        dispatch_queue_create("org.xoria.XPCDemo.SessionQueue", DISPATCH_QUEUE_SERIAL);

	xpc_session_t session = xpc_session_create_xpc_service(
	        "org.xoria.XPCDemo.MyService", queue, XPC_SESSION_CREATE_INACTIVE, &error);

	if (session == NULL) {
		char *description = xpc_rich_error_copy_description(error);
		os_log_error(Log, "failed to connect to service: %s", description);
		return 1;
	}

	xpc_session_set_incoming_message_handler(session, ^(xpc_object_t message) {
		IncomingMessageHandler(message);
	});

	bool didActivate = xpc_session_activate(session, &error);
	if (!didActivate) {
		char *description = xpc_rich_error_copy_description(error);
		os_log_error(Log, "failed to activate session: %s", description);
		return 1;
	}

	xpc_object_t message = CreateMessage(bookmark);
	error = xpc_session_send_message(session, message);
	if (error != NULL) {
		char *description = xpc_rich_error_copy_description(error);
		os_log_error(Log, "failed to send message: %s", description);
		return 1;
	}
	os_log_info(Log, "sent message!");

	os_log_info(Log, "going to start waiting...");
	dispatch_main();
}
