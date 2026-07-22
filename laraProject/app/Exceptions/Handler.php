<?php

namespace App\Exceptions;

use Illuminate\Database\QueryException;
use Illuminate\Foundation\Exceptions\Handler as ExceptionHandler;
use Illuminate\Http\Request;
use Throwable;

class Handler extends ExceptionHandler
{
    /**
     * The list of the inputs that are never flashed to the session on validation exceptions.
     *
     * @var array<int, string>
     */
    protected $dontFlash = [
        'current_password',
        'password',
        'password_confirmation',
    ];

    /**
     * Register the exception handling callbacks for the application.
     */
    public function register(): void
    {
        $this->reportable(function (Throwable $e) {
            //
        });
    }

    /**
     * Render an exception into an HTTP response.
     *
     * Intercepts MySQL connection errors (2002: connection refused,
     * 2003: can't connect, 2006: server gone away) and returns a
     * 503 JSON response so clients receive a clean error instead of
     * an unhandled stack trace.
     *
     * @param  Request    $request
     * @param  Throwable  $exception
     * @return \Symfony\Component\HttpFoundation\Response
     */
    public function render($request, Throwable $exception)
    {
        // MySQL error codes that indicate the database is unreachable
        $dbConnectionErrors = [2002, 2003, 2006];

        if (
            $exception instanceof QueryException &&
            isset($exception->errorInfo[1]) &&
            in_array($exception->errorInfo[1], $dbConnectionErrors, strict: true)
        ) {
            return response()->json(['error' => 'Service temporarily unavailable'], 503);
        }

        return parent::render($request, $exception);
    }
}
