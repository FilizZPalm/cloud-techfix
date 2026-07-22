<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
    <head>
        <meta charset="utf-8">
        <link rel="stylesheet" type="text/css" href="{{ asset('css/style_sheet.css') }}" >
        <linK rel="icon" href="{{ asset('img/logo_header.svg') }}">
        
        <title>@yield('title') | TechFix </title>
    </head>

    <body>

        @include('layouts/_header')

        @include('layouts/admin_navbar', ['cur_page' => $__env->yieldContent('cur_page')])

        @yield('content')

        @include('layouts/_footer')
    </body>
</html>