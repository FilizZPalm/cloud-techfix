@extends('layouts.public_template')

@section('title', 'Login')

@section('cur_page','LOGIN')

@section('content')
    <section class="wrapper">
        <div class="input-box">
            {{ html()->form()->route('login')->open() }}
            @csrf
            <h1> Benvenuto </h1>
            <span> 
                {{ html()->text('username')->class(['input'])->id('username')->required() }}
                {{ html()->label('Nome Utente', 'username') }}
                
            </span>

            <span>
                {{ html()->password('password')->class(['input'])->id('password')->required() }}
                {{ html()->label('Password', 'password') }}
            </span>

            <span style="width: 300px">
                @if ($errors->first('username'))

                @foreach ($errors->get('username') as $message)
                    <p class=error_text_login>{{ $message }}</p>
                @endforeach
                @endif
            </span>

            <span>
            @if ($errors->first('password'))
                @foreach ($errors->get('password') as $message)
                    <p class=error_text_login>{{ $message }}</p>
                @endforeach

            @endif
            </span>
            {{ html()->submit('Accedi')->class(['btn']) }}

            
            {{ html()->form()->close() }}   
        </div>
    </section>
@endsection