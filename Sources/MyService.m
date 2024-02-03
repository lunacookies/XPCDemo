#include <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <os/log.h>
#include <stdio.h>
#include <xpc/xpc.h>

os_log_t Log;

const char *ReadDataAtBookmark(const char *bookmarkBytes, size_t bookmarkByteCount) {
	NSError *error = nil;

	NSData *bookmark = [NSData dataWithBytes:bookmarkBytes length:bookmarkByteCount];

	os_log_info(Log, "bookmark: %@", bookmark);

	BOOL isStale = NO;
	NSURL *URLFromBookmark = [NSURL URLByResolvingBookmarkData:bookmark
	                                                   options:NSURLBookmarkResolutionWithoutUI
	                                             relativeToURL:nil
	                                       bookmarkDataIsStale:&isStale
	                                                     error:&error];
	if (URLFromBookmark == nil) {
		os_log_error(Log, "failed to resolve bookmark: %@", error.localizedDescription);
		return NULL;
	}

	os_log_info(Log, "got URL from bookmark: %@", URLFromBookmark);
	if (isStale) {
		os_log_info(Log, "bookmark was stale!");
	}

	NSString *content = [NSString stringWithContentsOfURL:URLFromBookmark
	                                             encoding:NSUTF8StringEncoding
	                                                error:&error];
	if (content == nil) {
		os_log_error(Log, "failed to read file pointed to by bookmark: %@",
		        error.localizedDescription);
		return NULL;
	}

	os_log_info(Log, "content: %@", content);

	[URLFromBookmark stopAccessingSecurityScopedResource];

	return [content cStringUsingEncoding:NSUTF8StringEncoding];
}

xpc_object_t RespondToMessage(xpc_object_t message) {
	os_log_info(Log, "got message: %s", xpc_copy_description(message));
	xpc_object_t response = xpc_dictionary_create_empty();

	size_t bookmarkDataLength = 0;
	const void *bookmarkData =
	        xpc_dictionary_get_data(message, "bookmark", &bookmarkDataLength);

	if (bookmarkData == NULL) {
		xpc_object_t message = xpc_string_create("key “bookmark” not present!");
		xpc_dictionary_set_value(response, "error", message);
		return response;
	}

	const char *content = ReadDataAtBookmark(bookmarkData, bookmarkDataLength);
	if (content == NULL) {
		xpc_object_t message = xpc_string_create("failed to read data at bookmark");
		xpc_dictionary_set_value(response, "error", message);
		return response;
	}

	xpc_dictionary_set_value(response, "content", xpc_string_create(content));
	return response;
}

void IncomingSessionHandler(xpc_session_t session) {
	os_log_info(Log, "got session: %s", xpc_session_copy_description(session));
	xpc_session_set_incoming_message_handler(session, ^(xpc_object_t message) {
		xpc_object_t response = RespondToMessage(message);
		xpc_rich_error_t error = xpc_session_send_message(session, response);
		if (error != NULL) {
			char *description = xpc_rich_error_copy_description(error);
			os_log_error(Log, "failed to send message: %s", description);
		}
	});
}

int main() {
	Log = os_log_create("org.xoria.XPCDemo.MyService", "main");
	NSError *e = nil;
	xpc_rich_error_t error = NULL;

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

	NSString *secret = [NSString stringWithContentsOfURL:secretURL
	                                            encoding:NSUTF8StringEncoding
	                                               error:&e];
	if (secret == nil) {
		os_log_info(Log, "as expected, failed to read secret at %@: %@", secretURL,
		        e.localizedDescription);
	} else {
		os_log_error(Log, "somehow read secret without bookmark: %@", secret);
	}

	dispatch_queue_t queue = dispatch_queue_create(
	        "org.xoria.XPCDemo.MyService.ListenerQueue", DISPATCH_QUEUE_SERIAL);

	xpc_listener_incoming_session_handler_t handler = ^(xpc_session_t session) {
		IncomingSessionHandler(session);
	};

	xpc_listener_t listener = xpc_listener_create(
	        "org.xoria.XPCDemo.MyService", queue, XPC_LISTENER_CREATE_NONE, handler, &error);
	if (listener == NULL) {
		char *description = xpc_rich_error_copy_description(error);
		os_log_error(Log, "failed to create listener: %s", description);
		return 1;
	}

	dispatch_main();
}
